const std = @import("std");
const Writer = std.Io.Writer;
const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;

const Codes = struct {
    const Str = []const u8;

    setCursorRowAbsolute: Str,
    moveCursorUp: Str,
    moveCursorDown: Str,
};

pub const codes: Codes = .{
    .setCursorRowAbsolute = "\x1b[{d}G",
    .moveCursorUp = "\x1b[{d}A",
    .moveCursorDown = "\x1b[{d}B",
};

pub fn setCursorPos(context: *RenderContext, row: i32, col: usize, writer: *Writer) !void {
    const rowDiff = row - context.rowOffset;
    if (rowDiff < 0) {
        try writer.print(codes.moveCursorUp, .{rowDiff * -1});
    } else {
        try writer.print(codes.moveCursorDown, .{rowDiff});
    }
    try writer.flush();
    try writer.print(codes.setCursorRowAbsolute, .{col});
    try writer.flush();

    context.rowOffset = row;
}
