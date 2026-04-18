const std = @import("std");

const zig_tui = @import("zig_tui");

const context = @import("context.zig");
const renderer = @import("renderer.zig");
const sequences = @import("sequences.zig");
const utils = @import("utils.zig");

const c = @cImport({
    @cInclude("signal.h");
});

var isResized = std.atomic.Value(bool).init(false);

fn sigWinchHandler(sig: i32) callconv(.c) void {
    _ = sig;
    isResized.store(true, .seq_cst);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    _ = allocator;

    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdoutBuf);
    const writer = &stdout.interface;

    var act: std.posix.Sigaction = .{
        .handler = .{ .handler = sigWinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &act, null);

    var winchOnly = std.posix.sigemptyset();
    std.posix.sigaddset(&winchOnly, std.posix.SIG.WINCH);
    std.posix.sigprocmask(std.posix.SIG.BLOCK, &winchOnly, null);

    const waitMask = std.posix.sigemptyset();

    var renderContext: context.RenderContext = .{};

    try sequences.disableAutoWrap(writer);

    var size = try utils.getWinSize();
    try renderer.render(&renderContext, size, writer);

    while (true) {
        _ = c.sigsuspend(@ptrCast(&waitMask));

        if (isResized.swap(false, .seq_cst)) {
            size = try utils.getWinSize();
            try renderer.render(&renderContext, size, writer);
        }
    }
}
