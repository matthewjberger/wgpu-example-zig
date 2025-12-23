const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zalgebra_dep = b.dependency("zalgebra", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "triangle",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zalgebra", .module = zalgebra_dep.module("zalgebra") },
            },
        }),
    });

    exe.addIncludePath(.{ .cwd_relative = "include" });

    if (target.result.os.tag == .windows) {
        exe.addLibraryPath(.{ .cwd_relative = "." });
        exe.addLibraryPath(.{ .cwd_relative = "lib" });
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("wgpu_native");
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("shell32");
        exe.linkSystemLibrary("ole32");
        exe.linkSystemLibrary("oleaut32");
        exe.linkSystemLibrary("advapi32");
        exe.linkSystemLibrary("ws2_32");
        exe.linkSystemLibrary("userenv");
        exe.linkSystemLibrary("bcrypt");
        exe.linkSystemLibrary("ntdll");
        exe.linkSystemLibrary("d3dcompiler_47");
        exe.linkSystemLibrary("opengl32");
    } else if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("wgpu_native");
    } else if (target.result.os.tag == .macos) {
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("wgpu_native");
    }

    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the triangle example");
    run_step.dependOn(&run_cmd.step);
}
