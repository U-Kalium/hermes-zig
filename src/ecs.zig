const std = @import("std");
const ArrayList = std.ArrayList;
const StringHashmap = std.StringHashMap;
const Type = std.builtin.Type;
const TypeId = std.builtin.TypeId;
const Allocator = std.mem.Allocator;

const sparset = @import("sparseset.zig");
const AnySet = sparset.AnySet;
const SparseSet = sparset.SparseSet;

const ENTITY_SET_CAPACITY = 255;
const Components = struct {
    map: StringHashmap(AnySet),

    allocator: Allocator,

    const ComponentsError = error{
        NonPointerFieldWhichIsntEntityId,
        UnkownComponentQueryStructMember,
    };

    fn init(allocator: Allocator) Components {
        return .{ .map = .init(allocator), .allocator = allocator };
    }

    fn deinit(self: *Components) void {
        var iter = self.map.iterator();

        while (iter.next()) |set| {
            set.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();
        self.* = undefined;
    }

    pub fn addComponent(
        self: *Components,
        comptime T: type,
        comp: T,
        entity_id: EntityId,
    ) !void {
        if (self.map.getPtr(@typeName(T))) |any_set| {
            var set: *SparseSet(T) = any_set.downcast(T);
            try set.insert(entity_id, comp);
        } else {
            var set = try self.allocator.create(SparseSet(T));

            set.* = try .init(self.allocator, ENTITY_SET_CAPACITY);
            try set.insert(entity_id, comp);
            const any_set = AnySet.init(*SparseSet(T), set);
            try self.map.put(@typeName(T), any_set);
        }
    }

    fn query(self: *Components, comptime E: type) !E {
        const allocator = std.heap.page_allocator;
        const info = @typeInfo(E);
        const Q = info.pointer.child;
        const fields = @typeInfo(info.pointer.child).@"struct".fields;

        var query_not_possible = false;

        var sets: [fields.len]?*AnySet = undefined;
        var sets_len: [fields.len]usize = undefined;
        var smallest_idx: usize = 0;
        var smallest_len: usize = std.math.maxInt(usize);

        inline for (fields, 0..) |field, field_idx| {
            const field_type_info = @typeInfo(field.type);
            switch (field_type_info) {
                .pointer => |p| {
                    const deref_field_type = p.child;
                    const type_name = @typeName(deref_field_type);
                    const maybe_set = self.map.getPtr(type_name);
                    sets_len[field_idx] = if (maybe_set) |set| set.len() else 0;
                    sets[field_idx] = maybe_set;
                },
                else => {},
            }
        }
        for (sets_len, 0..) |len, idx| {
            if (len < smallest_len) {
                smallest_idx = idx;
                smallest_len = len;
            }
        }
        var entity_ids: ArrayList(EntityId) = .empty;
        defer entity_ids.deinit(allocator);
        for (if (sets[smallest_idx]) |set| set.getEntities() else &.{}) |entity| {
            if (for (sets, 0..) |maybe_set, idx| {
                if (idx == smallest_idx and if (maybe_set) |set| set.contains(entity) else false) {
                    break true;
                }
            } else false) {
                try entity_ids.append(allocator, entity);
            }
        }
        var comps = try ArrayList(Q).initCapacity(allocator, entity_ids.items.len);
        for (entity_ids.items) |id| {
            var query_struct: Q = undefined;
            inline for (fields, 0..) |field, set_idx| {
                const field_deref = @typeInfo(field.type);
                switch (field_deref) {
                    .int => {
                        if (std.mem.eql(u8, field.name, "id") and field.type == EntityId) {
                            @field(query_struct, field.name) = id;
                        } else {
                            return ComponentsError.NonPointerFieldWhichIsntEntityId;
                        }
                    },
                    .pointer => |p| {
                        const set_deref = p.child;
                        if (sets[set_idx]) |set| {
                            const typed_set = set.downcast(set_deref);
                            if (typed_set.get(id)) |data| {
                                @field(query_struct, field.name) = data;
                            } else {
                                query_not_possible = true;
                            }
                            // @field(query_struct, field.name) = typed_set.get(id).?;
                        }
                    },
                    else => {
                        return ComponentsError.UnkownComponentQueryStructMember;
                    },
                }
                // if (std.mem.eql(u8, field.name, "id") and field.type == EntityId) {
                //     @field(query_struct, field.name) = id;
                // } else {
                //     const set_deref = @typeInfo(field.type).pointer.child;
                //     if (sets[set_idx]) |set| {
                //         const typed_set = set.downcast(set_deref);
                //         if (typed_set.get(id)) |data| {
                //             @field(query_struct, field.name) = data;
                //         } else {
                //             query_not_possible = true;
                //         }
                //         // @field(query_struct, field.name) = typed_set.get(id).?;
                //     }
                // }
            }
            comps.appendAssumeCapacity(query_struct);
        }
        if (query_not_possible) {
            return &[_]Q{};
        }
        return comps.toOwnedSlice(allocator);
    }
};

const System = struct {
    func: *const anyopaque,
    run_func: *const fn (self_any: *const anyopaque, comps: *Components, last_entity_id: *EntityId) anyerror!void,

    const Self = @This();

    fn init(f: anytype) System {
        const T = @TypeOf(f);
        const info = @typeInfo(T);
        const fn_info = info.@"fn";
        const params = comptime fn_info.params;
        comptime {
            if (info != .@"fn") @compileError("Expected a function");
            // if (fn_info.return_type != anyerror!void) @compileError("Expected function with return type of anyerror!void");
            if (fn_info.params.len == 0) @compileError("Expected function with params");
            const return_info = @typeInfo(fn_info.return_type.?);
            if (return_info != .error_union) @compileError("Expected function with an error union return type");

            for (params) |param_opt| {
                // const param = @typeInfo(param_opt.type.?);
                _ = isParamValidQuery(param_opt.type.?);
            }
        }

        const run_func = comptime struct {
            fn run(self_any: *const anyopaque, comps: *Components, last_entity_id: *EntityId) !void {
                const self: *const T = @ptrCast(@alignCast(self_any));

                const args_type: type = comptime t: {
                    var field_types: [params.len]type = undefined;

                    for (params, 0..) |param, i| {
                        field_types[i] = param.type.?;
                    }

                    break :t @Tuple(&field_types);
                };

                var args: args_type = undefined;
                const args_info = @typeInfo(args_type).@"struct";
                inline for (args_info.fields) |field| {
                    if (field.type == EntityManager) {
                        const manager = EntityManager{ .last_entity_id = last_entity_id, .components = comps };
                        @field(args, field.name) = manager;
                    } else {
                        const query = try comps.query(field.type);
                        @field(args, field.name) = query;
                    }
                }
                try @call(.auto, self, args);
            }
        };

        return .{
            .func = @ptrCast(&f),
            .run_func = run_func.run,
        };
    }

    fn run(self: *Self, comps: *Components, last_entity_id: *EntityId) !void {
        try self.run_func(self.func, comps, last_entity_id);
    }
};

pub const EntityId = u64;

pub const World = struct {
    components: Components,
    last_entity_id: EntityId,
    systems: StringHashmap(ArrayList(System)),

    allocator: Allocator,

    const Self = @This();

    const WorldError = error{TriedRunningNoneExistingSystemGroup};

    pub fn init(allocator: Allocator) World {
        return World{ .components = Components.init(allocator), .last_entity_id = 0, .systems = .init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        self.components.deinit();
        var systems_iterator = self.systems.iterator();
        while (systems_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.systems.deinit();
        self.* = undefined;
    }

    pub fn createEntity(self: *World, entity: anytype) !EntityId {
        const T = @TypeOf(entity);
        const info = @typeInfo(T);
        comptime {
            if (info != .@"struct" or !info.@"struct".is_tuple)
                @compileError("Expected a tuple, found " ++ @typeName(T));
        }
        self.last_entity_id += 1;

        inline for (info.@"struct".fields) |field| {
            try self.components.addComponent(field.type, @field(entity, field.name), self.last_entity_id);
        }

        return self.last_entity_id;
    }

    pub fn addSystem(self: *Self, f: anytype, comptime group: type) !void {
        const group_name = @typeName(group);
        const sys = System.init(f);
        var group_systems = try self.systems.getOrPut(group_name);
        if (group_systems.found_existing) {
            try group_systems.value_ptr.append(self.allocator, sys);
        } else {
            var new_group_system: ArrayList(System) = .empty;
            try new_group_system.append(self.allocator, sys);
            group_systems.value_ptr.* = new_group_system;
        }
        // try self.systems.put(group_name, sys);
    }

    pub fn runSystem(self: *Self, comptime group: type) !void {
        const group_systems = self.systems.getPtr(@typeName(group)) orelse return WorldError.TriedRunningNoneExistingSystemGroup;
        for (group_systems.items) |*sys| {
            try sys.run(&self.components, &self.last_entity_id);
        }
    }
};

pub const EntityManager = struct {
    last_entity_id: *EntityId,
    components: *Components,

    const Self = @This();

    pub fn createEntity(self: *const Self, entity: anytype) !EntityId {
        const T = @TypeOf(entity);
        const info = @typeInfo(T);
        comptime {
            if (info != .@"struct" or !info.@"struct".is_tuple)
                @compileError("Expected a tuple, found " ++ @typeName(T));
        }
        self.last_entity_id.* += 1;

        inline for (info.@"struct".fields) |field| {
            try self.components.addComponent(field.type, @field(entity, field.name), self.last_entity_id.*);
        }

        return self.last_entity_id.*;
    }

    pub fn addComponents(self: *const Self, entity_id: EntityId, components: anytype) !void {
        const comp_type = @TypeOf(components);
        const comp_info = @typeInfo(comp_type);
        comptime {
            if (comp_info != .@"struct") @compileError("Expected components to be a struct");
        }
        const fields = comp_info.@"struct".fields;
        inline for (fields) |field| {
            try self.components.addComponent(field.type, @field(components, field.name), entity_id);
        }
    }

    pub fn addCOmponent(self: *const Self, comptime T: type, comp: T, entity_id: EntityId) !void {
        try self.components.addComponent(T, comp, entity_id);
    }
};

fn isParamValidQuery(param: type) bool {
    if (param == EntityManager) {
        return true;
    } else {
        const info = @typeInfo(param);
        if (info == .pointer) {
            const child = @typeInfo(info.pointer.child);
            if (child == .@"struct") return true;
        }
    }
    @compileError("Expected function param to be a slice or of type EntityManager");
}
