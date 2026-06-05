const std = @import("std");
const ecs = @import("hermes");
// const hermes = @import("comptime target: []const u8")
const Io = std.Io;

const Foo = struct { bar: u32 };
const Bar = struct { buzz: []const u8 };
const Buzz = struct { a: f32 };

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var world = ecs.World.init(allocator);
    defer world.deinit();

    const foo = Foo{ .bar = 10 };
    const bar = Bar{ .buzz = "Your Mom" };
    const buzz = Buzz{ .a = 4.20 };

    const buzz2 = Buzz{ .a = 6.7 };
    const foo2 = Foo{ .bar = 69 };

    const foo3 = Foo{ .bar = 21 };

    _ = try world.createEntity(.{ foo, bar, buzz });
    _ = try world.createEntity(.{ foo2, buzz2 });
    _ = try world.createEntity(.{
        foo3,
    });

    try world.addSystem(printFooBarBuzz);
    try world.addSystem(modifyFooBarBuzz);
    try world.addSystem(printFooBarBuzz);

    try world.runSystem();
}

fn printFooBarBuzz(entities: []struct { foo: *const Foo, buzz: *const Buzz }, entities2: []struct { bar: *const Bar }) void {
    std.debug.print("Foo Buzz Entities\n", .{});
    for (entities) |entity| {
        std.debug.print("{}\n", .{entity});
    }
    std.debug.print("Bar Entities\n", .{});
    for (entities2) |entity| {
        std.debug.print("{}\n", .{entity});
    }
}

fn modifyFooBarBuzz(entities: []struct { foo: *Foo, buzz: *Buzz }, entities2: []struct { bar: *Bar }) void {
    for (entities) |entity| {
        entity.foo.bar += 1;
        entity.buzz.a += 1.0;
    }
    for (entities2) |entity| {
        entity.bar.buzz = "Modified!";
    }
}
