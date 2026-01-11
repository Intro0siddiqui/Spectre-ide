const std = @import("std");

pub fn build(b: *std.Build) void {
    // Create module with source, target and optimize
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{
            .default_target = .{
                .cpu_arch = .x86_64,
                .os_tag = .freestanding,
            },
        }),
        .optimize = b.standardOptimizeOption(.{
            .preferred_optimize_mode = .ReleaseSmall,
        }),
        .unwind_tables = .none,
        .single_threaded = true,
    });

    const exe = b.addExecutable(.{
        .name = "spectre-ide",
        .root_module = mod,
    });
    
    b.installArtifact(exe);
    
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run Spectre-IDE");
    run_step.dependOn(&run_cmd.step);
}
