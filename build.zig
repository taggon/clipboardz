const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define the module for external consumption
    const clipboardz_mod = b.addModule("clipboardz", .{
        .root_source_file = b.path("src/main.zig"),
    });

    // Define the static library
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "clipboardz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    if (target.result.os.tag == .macos) {
        lib.linkSystemLibrary("objc");
        lib.linkFramework("Foundation");
        lib.linkFramework("AppKit");
        // Also link for the module if used directly?
        // Modules don't hold linking info in the same way, but the consumer needs to link.
        // But for the static library artifact, we link here.
    } else if (target.result.os.tag == .linux) {
        lib.linkSystemLibrary("X11");
        lib.linkLibC();
    }

    b.installArtifact(lib);

    // Example executable
    const exe = b.addExecutable(.{
        .name = "simple-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Import the clipboardz module
    exe.root_module.addImport("clipboardz", clipboardz_mod);

    if (target.result.os.tag == .macos) {
        exe.linkSystemLibrary("objc");
        exe.linkFramework("Foundation");
        exe.linkFramework("AppKit");
    } else if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("X11");
        exe.linkLibC();
    } else if (target.result.os.tag == .windows) {
        exe.linkLibC();
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run-example", "Run the simple example");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    if (target.result.os.tag == .macos) {
        lib_unit_tests.linkSystemLibrary("objc");
        lib_unit_tests.linkFramework("Foundation");
        lib_unit_tests.linkFramework("AppKit");
    } else if (target.result.os.tag == .linux) {
        lib_unit_tests.linkSystemLibrary("X11");
        lib_unit_tests.linkLibC();
    }

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Integration test: Run the example to verify the library works end-to-end
    const run_example = b.addRunArtifact(exe);
    run_example.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_example.step);
}
