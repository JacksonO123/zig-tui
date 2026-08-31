const std = @import("std");

const check_targets: []const []const u8 = &.{
    "x86_64-linux-gnu",
    "x86_64-linux-musl",
    "aarch64-linux-gnu",
    "x86_64-macos",
    "aarch64-macos",
    "x86_64-windows-gnu",
    "aarch64-windows-gnu",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = addExampleExe(b, target, optimize);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const check_step = b.step("check", "Compile for every supported target");

    for (check_targets) |query| {
        const parsed = std.Target.Query.parse(.{ .arch_os_abi = query }) catch
            std.debug.panic("invalid target query: {s}", .{query});

        const checked = addExampleExe(b, b.resolveTargetQuery(parsed), optimize);
        check_step.dependOn(&checked.step);
    }
}

fn addTuiLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addLibrary(.{
        .name = "zig_tui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
}

fn addExampleExe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const tui_lib = addTuiLib(b, target, optimize);

    return b.addExecutable(.{
        .use_llvm = true,
        .name = "zig_tui_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "zig_tui",
                    .module = tui_lib.root_module,
                },
            },
        }),
    });
}
