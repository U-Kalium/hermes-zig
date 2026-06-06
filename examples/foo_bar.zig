const std = @import("std");
const ecs = @import("hermes");
// const hermes = @import("comptime target: []const u8")
const Io = std.Io;

const Foo = struct { bar: u32 };
const Bar = struct { buzz: []const u8 };
const Buzz = struct { a: f32 };

const PrintSystems = struct {};
const ModifySystems = struct {};
const InitSystems = struct {};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var world = ecs.World.init(allocator);
    defer world.deinit();

    try world.addSystem(initEntities, InitSystems);
    try world.addSystem(printFooBarBuzz, PrintSystems);
    try world.addSystem(modifyFooBarBuzz, ModifySystems);

    try world.runSystem(InitSystems);
    try world.runSystem(PrintSystems);
    try world.runSystem(ModifySystems);
    try world.runSystem(PrintSystems);
}

fn initEntities(manager: ecs.EntityManager) !void {
    // var manager = manager;
    const foo = Foo{ .bar = 10 };
    const bar = Bar{ .buzz = "Your Mom" };
    const buzz = Buzz{ .a = 4.20 };

    const buzz2 = Buzz{ .a = 6.7 };
    const foo2 = Foo{ .bar = 69 };

    const foo3 = Foo{ .bar = 21 };

    _ = manager.createEntity(.{ foo, bar, buzz }) catch @panic("Could not create entity");
    _ = manager.createEntity(.{ foo2, buzz2 }) catch @panic("Could not create entity");
    _ = manager.createEntity(.{
        foo3,
    }) catch @panic("Could not create entity");
}

fn printFooBarBuzz(entities: []struct { foo: *const Foo, buzz: *const Buzz }, entities2: []struct { bar: *const Bar }) !void {
    std.debug.print("Foo Buzz Entities\n", .{});
    for (entities) |entity| {
        std.debug.print("{}\n", .{entity});
    }
    std.debug.print("Bar Entities\n", .{});
    for (entities2) |entity| {
        std.debug.print("{}\n", .{entity});
    }
}

fn modifyFooBarBuzz(entities: []struct { foo: *Foo, buzz: *Buzz }, entities2: []struct { bar: *Bar }) !void {
    for (entities) |entity| {
        entity.foo.bar += 1;
        entity.buzz.a += 1.0;
    }
    for (entities2) |entity| {
        entity.bar.buzz = "Modified!";
    }
}
