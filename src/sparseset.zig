const std = @import("std");
const ArrayList = std.ArrayList;
const StringHashmap = std.StringHashMap;
const Type = std.builtin.Type;
const TypeId = std.builtin.TypeId;
const Allocator = std.mem.Allocator;

const ecs = @import("ecs.zig");

pub fn SparseSet(comptime value: type) type {
    return struct {
        allocator: Allocator,

        sparse: ArrayList(?usize),
        dense: ArrayList(ecs.EntityId),
        values: ArrayList(value),

        const Self = @This();
        const isSet = true;

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var sparse = try ArrayList(?usize).initCapacity(allocator, capacity);
            sparse.appendNTimesAssumeCapacity(null, capacity);
            return .{ .allocator = allocator, .sparse = sparse, .dense = .empty, .values = .empty };
        }

        pub fn deinit(self: *Self) void {
            self.sparse.deinit(self.allocator);
            self.dense.deinit(self.allocator);
            self.values.deinit(self.allocator);

            self.* = undefined;
        }

        pub fn get(self: *Self, entity_id: ecs.EntityId) ?*value {
            if (entity_id >= self.sparse.items.len) {
                return null;
            }

            if (self.sparse.items[entity_id]) |dense_idx| {
                const component = &self.values.items[dense_idx];
                return component;
            } else {
                return null;
            }
        }

        fn opaqueFree(ptr: *anyopaque, allocator: Allocator) void {
            const typed: *Self = @ptrCast(@alignCast(ptr));

            allocator.destroy(typed);
        }

        pub fn len(self: *Self) usize {
            return self.dense.items.len;
        }

        fn opaqueLen(ptr: *anyopaque) usize {
            const typed: *Self = @ptrCast(@alignCast(ptr));
            return typed.len();
        }

        pub fn getEntities(self: *Self) []ecs.EntityId {
            return self.dense.items;
        }

        fn opaqueGetEntities(ptr: *anyopaque) []ecs.EntityId {
            const typed: *Self = @ptrCast(@alignCast(ptr));
            return typed.getEntities();
        }

        pub fn contains(self: *Self, entity_id: ecs.EntityId) bool {
            return (entity_id < self.sparse.items.len) and self.sparse.items[entity_id] != null;
        }

        fn opaqueContains(ptr: *anyopaque, entity_id: ecs.EntityId) bool {
            const typed: *Self = @ptrCast(@alignCast(ptr));
            return typed.contains(entity_id);
        }

        pub fn insert(self: *Self, entity_id: ecs.EntityId, comp: value) !void {
            if (entity_id >= self.sparse.items.len) {
                try self.sparse.resize(self.allocator, entity_id + entity_id / 2);
                self.sparse.appendNTimesAssumeCapacity(null, entity_id / 2);
            }

            if (self.sparse.items[entity_id]) |dense_idx| {
                self.values.items[dense_idx] = comp;
            } else {
                const dense_idx = self.dense.items.len;
                self.sparse.items[entity_id] = dense_idx;
                try self.dense.append(self.allocator, entity_id);
                try self.values.append(self.allocator, comp);
            }
        }
    };
}

pub const AnySet = struct {
    set: *anyopaque,

    deinit_fn: *const fn (ptr: *anyopaque, allocator: Allocator) void,
    len_fn: *const fn (ptr: *anyopaque) usize,
    get_entities_fn: *const fn (ptr: *anyopaque) []ecs.EntityId,
    contains_fn: *const fn (ptr: *anyopaque, entity_id: ecs.EntityId) bool,

    const Self = @This();

    const AnySetError = error{DowncastTypeDoesntMatchSetValu};

    pub fn init(comptime T: type, p: T) AnySet {
        const p_info = @typeInfo(T);
        const child = p_info.pointer.child;
        comptime {
            if (p_info != .pointer) @compileError("Expected a pointer");
            if (!@hasDecl(child, "isSet")) @compileError("Expected pointer child to be a Set found: ");
        }
        return .{ .set = @ptrCast(p), .deinit_fn = child.opaqueFree, .len_fn = child.opaqueLen, .get_entities_fn = child.opaqueGetEntities, .contains_fn = child.opaqueContains };
    }

    pub fn len(self: *Self) usize {
        return self.len_fn(self.set);
    }

    pub fn getEntities(self: *Self) []ecs.EntityId {
        return self.get_entities_fn(self.set);
    }

    pub fn contains(self: *Self, entity_id: ecs.EntityId) bool {
        return self.contains_fn(self.set, entity_id);
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.deinit_fn(self.set, allocator);

        self.* = undefined;
    }

    pub fn downcast(
        self: *Self,
        comptime T: type,
    ) *SparseSet(T) {
        return @ptrCast(@alignCast(@constCast(self.set)));
    }
};
