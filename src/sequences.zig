const std = @import("std");
const Writer = std.Io.Writer;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;

const Codes = struct {
    const Str = []const u8;

    setCursorColAbsolute: Str,
    setCursorPosAbsolute: Str,
    moveCursorUp: Str,
    moveCursorDown: Str,
    eraseDisplayAfterCursor: Str,
    disableAutoWrap: Str,
    enableAutoWrap: Str,
    clearScreen: Str,
};

pub const codes: Codes = .{
    .setCursorColAbsolute = "\x1b[{d}G",
    .setCursorPosAbsolute = "\x1b[{d};{d}H", // row;col
    .moveCursorUp = "\x1b[{d}A",
    .moveCursorDown = "\x1b[{d}B",
    .eraseDisplayAfterCursor = "\x1b[0J",
    .disableAutoWrap = "\x1b[?7l",
    .enableAutoWrap = "\x1b[?7h",
    .clearScreen = "\x1b[2J",
};

pub fn setCursorPos(context: *RenderContext, row: i32, col: usize, writer: *Writer) !void {
    const rowDiff = row - context.rowOffset;
    if (rowDiff < 0) {
        try writer.print(codes.moveCursorUp, .{rowDiff * -1});
    } else if (rowDiff != 0) {
        try writer.print(codes.moveCursorDown, .{rowDiff});
    }
    try writer.print(codes.setCursorColAbsolute, .{col});

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
}

pub fn eraseDisplayAfterCursor(writer: *Writer) !void {
    try writer.writeAll(codes.eraseDisplayAfterCursor);
}

pub fn disableAutoWrap(writer: *Writer) !void {
    try writer.writeAll(codes.disableAutoWrap);
}

pub fn enableAutoWrap(writer: *Writer) !void {
    try writer.writeAll(codes.enableAutoWrap);
}

pub fn clearScreen(writer: *Writer) !void {
    try writer.writeAll(codes.clearScreen);
}

pub fn setCursorPosAbsolute(row: usize, col: usize, writer: *Writer) !void {
    try writer.print(codes.setCursorPosAbsolute, .{ row, col });
}
