const std = @import("std");

pub fn main() void {
    std.debug.print("slice type: {}", .{@typeInfo([]struct { foo: u32 })});
}
