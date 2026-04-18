const std = @import("std");

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

    var buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&buf);
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

    // while (true) {
    //     // if (is_resized.load(.seq_cst)) {
    //     //     is_resized.store(false, .seq_cst);

    //     //     size = try utils.getWinSize();

    //     //     try renderer.render(size, writer);
    //     // }

    //     std.Thread.sleep(100 * std.time.ns_per_ms);
    // }
}
