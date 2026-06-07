const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "hermes",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const lib_module = b.addModule("hermes", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });

    const example_foo_bar = b.addExecutable(.{
        .name = "foo_bar",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/foo_bar.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    example_foo_bar.root_module.addImport("hermes", lib_module);

    // example_test.root_module.linkLibrary(lib);

    const tests_module = b.addModule("tests", .{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = tests_module,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("tests", "run tests");
    test_step.dependOn(&run_tests.step);

    b.installArtifact(lib);

    if (b.option(bool, "foo_bar", "Install the foo bar examples") orelse false) {
        b.installArtifact(example_foo_bar);
        const run_foo_bar = b.addRunArtifact(example_foo_bar);
        const run_step = b.step("run", "Run teh test");
        run_step.dependOn(&run_foo_bar.step);
    }
}
