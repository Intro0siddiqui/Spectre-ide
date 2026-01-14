const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create root module
    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "spectre",
        .root_module = root_mod,
    });

    // Link SDL2
    exe.linkSystemLibrary("SDL2");

    // Link FreeType for text rendering
    exe.linkSystemLibrary("freetype2");

    // Link C standard library (needed for SDL2/FreeType)
    exe.linkLibC();

    // Add C++ LSP client
    exe.addCSourceFiles(.{
        .files = &.{
            "cpp/lsp_client.cpp",
        },
        .flags = &.{
            "-std=c++17",
            "-fno-exceptions",
            "-fno-rtti",
        },
    });
    exe.linkLibCpp();

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Spectre-IDE");
    run_step.dependOn(&run_cmd.step);
}
