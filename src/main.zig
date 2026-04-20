const std = @import("std");
const builtin = @import("builtin");

const zig_tui = @import("zig_tui");

const app = @import("app.zig");
const context = @import("context.zig");
const renderer = @import("renderer.zig");
const sequences = @import("sequences.zig");
const terminalMod = @import("terminal.zig");
const utils = @import("utils.zig");

const c = @cImport({
    @cInclude("signal.h");
});

var isResized = std.atomic.Value(bool).init(false);

fn sigWinchHandler(sig: i32) callconv(.c) void {
    _ = sig;
    isResized.store(true, .seq_cst);
}

fn sigIntHandler(sig: i32) callconv(.c) void {
    _ = sig;
    var stdoutWriter = std.fs.File.stdout().writer(&.{});
    const stdout = &stdoutWriter.interface;
    sequences.enableAutoWrap(stdout) catch {};
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const globalArenaAllocator = arena.allocator();

    var gpAllocator = std.heap.GeneralPurposeAllocator(.{ .safety = builtin.mode == .Debug }){};
    defer _ = gpAllocator.deinit();
    const allocator = gpAllocator.allocator();

    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdoutBuf);
    const writer = &stdout.interface;

    var action: std.posix.Sigaction = .{
        .handler = .{ .handler = sigWinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &action, null);

    var resetAction: std.posix.Sigaction = .{
        .handler = .{ .handler = sigIntHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &resetAction, null);

    var winchOnly = std.posix.sigemptyset();
    std.posix.sigaddset(&winchOnly, std.posix.SIG.WINCH);
    std.posix.sigprocmask(std.posix.SIG.BLOCK, &winchOnly, null);

    const waitMask = std.posix.sigemptyset();

    try sequences.disableAutoWrap(writer);
    if (app.mockConfig.fullscreen) {
        try sequences.setCursorPosAbsolute(1, 1, writer);
    }

    var size = try utils.getWinSize();
    var terminal = terminalMod.Terminal.init(globalArenaAllocator);
    var renderContext = try context.RenderContext.init(allocator, &terminal, app.mockConfig, size);

    const el = try app.renderUI(&terminal);
    try renderer.render(allocator, &renderContext, el, size, writer);

    while (true) {
        _ = c.sigsuspend(@ptrCast(&waitMask));

        if (isResized.swap(false, .seq_cst)) {
            size = try utils.getWinSize();
            try renderer.render(allocator, &renderContext, el, size, writer);
        }
    }
}
