const std = @import("std");
const imgui = @import("imgui_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    const sdl_lib = sdl_dep.artifact("SDL3");

    const imgui_dep = b.dependency("imgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platform = imgui.Platform.sdl3,
        .renderer = imgui.Renderer.sdlrenderer3,
    });

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const imgui_artifact = imgui_dep.artifact("imgui");
    imgui_artifact.linkLibrary(sdl_lib);

    exe.linkLibrary(sdl_lib);
    exe.linkLibrary(imgui_dep.artifact("imgui"));
    exe.addIncludePath(imgui_dep.path("dcimgui"));
    exe.addIncludePath(imgui_dep.path("dcimgui/backends"));
    exe.addIncludePath(b.path("src"));

    exe.addCSourceFile(.{
        .file = b.path("src/lib/stb_image_impl.c"),
        .flags = &.{ "-DSTBI_NO_SIMD", "-DSTBI_NO_HDR" },
    });

    exe.linkLibC();

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "run the application");
    run_step.dependOn(&run_exe.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_tests.step);
}
