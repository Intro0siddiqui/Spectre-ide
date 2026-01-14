const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a static library
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "spectre_core",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/core/api.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    lib.root_module.pic = true;

    b.installArtifact(lib);
}
