const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ghostty-ls",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const babel = b.dependency("babel", .{});
    const lsp = babel.module("lsp");
    exe.root_module.addImport("lsp", lsp);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const plugin_generator = b.addExecutable(.{
        .name = "generate_plugins",
        .root_source_file = b.path("plugins.zig"),
        .target = b.host,
    });

    plugin_generator.root_module.addImport("lsp_plugins", babel.module("plugins"));
    b.step("gen_plugins", "Generate plugins").dependOn(&b.addRunArtifact(plugin_generator).step);
}
