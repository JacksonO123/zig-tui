const std = @import("std");
const c = @cImport({
    @cInclude("errno.h");
});

const zig_tui = @import("zig_tui");

const renderer = @import("renderer.zig");
const utils = @import("utils.zig");
const context = @import("context.zig");

var is_resized = std.atomic.Value(bool).init(false);

fn sigWinchHandler(sig: i32) callconv(.c) void {
    _ = sig;
    is_resized.store(true, .seq_cst);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdoutBuf);
    const writer = &stdout.interface;

    var act: std.posix.Sigaction = .{
        .handler = .{ .handler = sigWinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &act, null);

    const size = try utils.getWinSize();

    var renderContext: context.RenderContext = .{};

    try renderer.render(allocator, &renderContext, size, writer);
    try writer.flush();

    var stdinBuf: [1024]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&stdinBuf);
    const stdinReader = &stdin.interface;

    while (true) {
        if (is_resized.swap(false, .monotonic)) {
            std.debug.print("RESIZED\n", .{});
        }

        _ = stdinReader.takeByte() catch |err| {
            if (err == error.Interrupted) {
                std.debug.print("INTERRUPTED\n", .{});
                continue;
            }
            return err;
        };
    }
}
