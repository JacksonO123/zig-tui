const std = @import("std");
const Writer = std.Io.Writer;
const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;

const Codes = struct {
    const Str = []const u8;

    setCursorColAbsolute: Str,
    moveCursorUp: Str,
    moveCursorDown: Str,
};

pub const codes: Codes = .{
    .setCursorColAbsolute = "\x1b[{d}G",
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
    try writer.print(codes.setCursorColAbsolute, .{col});
    try writer.flush();

    context.rowOffset = row;
}

pub fn writeAscii(context: *RenderContext, ascii: []const u8, writer: *Writer) !void {
    var rowChange: i32 = 0;
    for (ascii) |char| {
        if (char == '\n') {
            rowChange += 1;
        }
    }

    context.rowOffset += rowChange;

    try writer.writeAll(ascii);
}

pub fn setCursorCol(col: usize, writer: *Writer) !void {
    try writer.print(codes.setCursorColAbsolute, .{col});
    try writer.flush();
}
