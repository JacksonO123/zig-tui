const std = @import("std");
const builtin = @import("builtin");

const c = @import("c");
const zig_tui = @import("zig_tui");

const app = @import("app.zig");
const context = @import("context.zig");
const renderer = @import("renderer.zig");
const sequences = @import("sequences.zig");
const utils = @import("utils.zig");

var resizePipeWriteFd: std.posix.fd_t = -1;

fn sigWinchHandler(sig: std.c.SIG) align(1) callconv(.c) void {
    _ = sig;
    const byte: u8 = 1;
    _ = std.c.write(resizePipeWriteFd, @ptrCast(&byte), 1);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena;
    const globalArenaAllocator = arena.allocator();

    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdoutBuf);
    const writer = &stdout.interface;

    var resizeFds: [2]std.posix.fd_t = undefined;
    if (std.c.pipe(&resizeFds) < 0) return error.PipeFailed;
    defer _ = std.c.close(resizeFds[0]);
    defer _ = std.c.close(resizeFds[1]);
    try utils.setNonblocking(resizeFds[0]);
    try utils.setNonblocking(resizeFds[1]);
    resizePipeWriteFd = resizeFds[1];

    var action: std.posix.Sigaction = .{
        .handler = .{ .handler = sigWinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &action, null);

    const stdinFd = std.Io.File.stdin().handle;
    var pollFds = [_]std.posix.pollfd{
        .{ .fd = stdinFd, .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = resizeFds[0], .events = std.posix.POLL.IN, .revents = 0 },
    };

    try utils.enableRawMode();
    defer utils.disableRawMode();

    try sequences.disableAutoWrap(writer);
    defer {
        sequences.enableAutoWrap(writer) catch {};
        writer.flush() catch {};
    }

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
    defer renderContext.deinit(gpa);

    var el = try app.renderUI(&renderContext.terminal);
    try renderer.render(gpa, &renderContext, el, size, writer);

    while (true) {
        _ = try std.posix.poll(&pollFds, -1);

        if ((pollFds[1].revents & std.posix.POLL.IN) != 0) {
            var drainBuf: [64]u8 = undefined;
            while (true) {
                _ = std.posix.read(resizeFds[0], &drainBuf) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => return err,
                };
            }

            size = try utils.getWinSize();
            try renderContext.onTerminalResize(size);
            el = try app.renderUI(&renderContext.terminal);
            try renderer.render(gpa, &renderContext, el, size, writer);
        }

        if ((pollFds[0].revents & std.posix.POLL.IN) != 0) {
            var buf: [64]u8 = undefined;
            const bytesRead = std.posix.read(stdinFd, &buf) catch |err| switch (err) {
                error.WouldBlock => continue,
                else => return err,
            };

            if (bytesRead == 0) continue;
            for (buf[0..bytesRead]) |byte| {
                switch (byte) {
                    'q', 0x03 => return,
                    else => {},
                }
            }
        }
    }
}
