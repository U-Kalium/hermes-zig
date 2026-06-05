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

    const lib_module = b.addModule("hermes", .{ .root_source_file = b.path("src/root.zig") });

    const example_test = b.addExecutable(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const scratch = b.addExecutable(.{
        .name = "scratch",
        .root_module = b.createModule(.{ .root_source_file = b.path("scratch.zig"), .target = target, .optimize = optimize }),
    });

    example_test.root_module.addImport("hermes", lib_module);

    // example_test.root_module.linkLibrary(lib);

    b.installArtifact(lib);

    if (b.option(bool, "with-test", "Install the test as well") orelse false) {
        b.installArtifact(example_test);
        const run_test = b.addRunArtifact(example_test);
        const run_step = b.step("run", "Run teh test");
        run_step.dependOn(&run_test.step);
    }
    if (b.option(bool, "scratch", "scratch") orelse false) {
        // b.installArtifact(scratch);
        const run_scratch = b.addRunArtifact(scratch);
        const run_step = b.step("run", "Run scratch");
        run_step.dependOn(&run_scratch.step);
    }
}
