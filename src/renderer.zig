const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const sequences = @import("sequences.zig");
const utils = @import("utils.zig");

pub fn render(
    childAllocator: Allocator,
    context: *RenderContext,
    size: utils.WinSize,
    writer: *Writer,
) !void {
    var arena = std.heap.ArenaAllocator.init(childAllocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    _ = allocator;

    try writer.writeByte('<');
    var i: usize = 0;
    while (i < size.col - 2) : (i += 1) {
        try writer.writeByte('-');
    }
    try sequences.writeAscii(context, ">\n[ ]", writer);
    try sequences.setCursorCol(2, writer);
    try writer.flush();

    // i = 0;
    // while (i < size.col - 2) : (i += 1) {
    //     std.Thread.sleep(100 * std.time.ns_per_ms);
    //     try sequences.setCursorPos(context, 1, i + 2, writer);
    //     try writer.writeByte('=');
    //     try sequences.setCursorPos(context, 2, 2, writer);
    // }

    // try writer.writeByte('\n');
    // try writer.flush();
}
