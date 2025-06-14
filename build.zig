const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "obj2mc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize
    });

    exe.linkLibC();
    exe.addIncludePath(b.path("thirdparty"));

    exe.root_module.addAnonymousImport("zalgebra", .{
        .root_source_file = b.path("thirdparty/zalgebra/src/main.zig")
    });

    const run = b.addRunArtifact(exe);
    if (b.args) |args| { run.addArgs(args); }
    const run_step = b.step("run", "Run the program");
    run_step.dependOn(&run.step);

    b.installArtifact(exe);
}
