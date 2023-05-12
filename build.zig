const std = @import("std");

pub fn build(b: *std.Build) void {
    const proxy_head = b.dependency("proxy_head", .{});
    const zlm = b.dependency("zlm", .{});

    const mirage_pkg = b.addModule("Mirage3D", .{
        .source_file = .{ .path = "src/Mirage3D.zig" },
    });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Mirage3D",
        .root_source_file = .{ .path = "src/demo.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("Mirage3D", mirage_pkg);
    exe.addModule("zlm", zlm.module("zlm"));
    exe.addModule("ProxyHead", proxy_head.module("ProxyHead"));
    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/testsuite.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
