const std = @import("std");
const builtin = @import("builtin");

const c = @import("c");
const zig_tui = @import("zig_tui");

const app = @import("app.zig");
const context = @import("context.zig");
const renderer = @import("renderer.zig");
const sequences = @import("sequences.zig");
const terminalMod = @import("terminal.zig");
const utils = @import("utils.zig");

var ioGlobal: ?*std.Io = null;
var isResized = std.atomic.Value(bool).init(false);

fn sigWinchHandler(sig: std.c.SIG) align(1) callconv(.c) void {
    _ = sig;
    isResized.store(true, .seq_cst);
}

fn sigIntHandler(sig: std.c.SIG) callconv(.c) void {
    _ = sig;

    var stdoutWriter = std.Io.File.stdout().writer(ioGlobal.?.*, &.{});
    const stdout = &stdoutWriter.interface;
    sequences.enableAutoWrap(stdout) catch {};
}

pub fn main(init: std.process.Init) !void {
    var io = init.io;
    ioGlobal = &io;
    const gpa = init.gpa;
    const arena = init.arena;
    const globalArenaAllocator = arena.allocator();

    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdoutBuf);
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
    var renderContext = try context.RenderContext.init(
        gpa,
        globalArenaAllocator,
        app.mockConfig,
        size,
    );

    const el = try app.renderUI(&renderContext.terminal);
    try renderer.render(gpa, &renderContext, el, size, writer, true);

    while (true) {
        _ = c.sigsuspend(@ptrCast(&waitMask));

        if (isResized.swap(false, .seq_cst)) {
            size = try utils.getWinSize();
            try renderContext.onTerminalResize();
            try renderer.render(gpa, &renderContext, el, size, writer, false);
        }
    }
}
