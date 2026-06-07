pub const ecs = @import("ecs.zig");
const std = @import("std");
pub const World = ecs.World;
pub const EntityManager = ecs.EntityManager;
const expect = std.testing.expect;

const Foo = struct { a: u32 };
const Bar = f32;
const Buzz = union(enum) { u32, f64 };

const TestSchedule = struct {};

test "Querying non existant entities" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var world = World.init(allocator);
    defer world.deinit();

    try world.addSystem(fooBarSys, TestSchedule);
    const bar: Bar = 10.0;
    _ = try world.createEntity(.{bar});
    _ = try world.createEntity(.{Foo{ .a = 10 }});
    try world.runSystem(TestSchedule);
    // try expect(true);
}
fn fooBarSys(entities: []struct {
    foo: *const Foo,
    bar: *Bar,
}) !void {
    for (entities) |entity| {
        entity.bar.* += 1.0;
        // std.debug.print("foo.a: {}", .{entity.foo.a});
    }
}

test "Query with entity id" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    var world = World.init(allocator);
    defer world.deinit();

    try world.addSystem(fooBarIdSys, TestSchedule);
    const id = try world.createEntity(.{Foo{ .a = 10 }});
    _ = try world.createEntity(.{id});

    try world.runSystem(TestSchedule);
}

const Entity = ecs.EntityId;

fn fooBarIdSys(
    entities: []struct {
        foo: *const Foo,
        id: ecs.EntityId,
    },
    entities2: []struct {
        entity: *Entity,
    },
) !void {
    for (entities, entities2) |entity, entity2| {
        try expect(entity2.entity.* == entity.id);
    }
}
