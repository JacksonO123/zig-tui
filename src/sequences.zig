const std = @import("std");
const Writer = std.Io.Writer;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const stylesMod = @import("styles.zig");

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
    resetStyles: Str,

    boldText: Str,
    disableBoldText: Str,

    underlineText: Str,
    disableUnderlineText: Str,

    italicText: Str,
    disableItalicText: Str,
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
    .resetStyles = "\x1b[0m",

    .boldText = "\x1b[1m",
    .disableBoldText = "\x1b[22m",

    .underlineText = "\x1b[4m",
    .disableUnderlineText = "\x1b[24m",

    .italicText = "\x1b[3m",
    .disableItalicText = "\x1b[23m",
};

pub fn setCursorPos(context: *RenderContext, row: i32, col: usize, writer: *Writer) !void {
    const rowDiff = row - context.state.rowOffset;
    if (rowDiff < 0) {
        try writer.print(codes.moveCursorUp, .{rowDiff * -1});
    } else if (rowDiff != 0) {
        try writer.print(codes.moveCursorDown, .{rowDiff});
    }
    try writer.print(codes.setCursorColAbsolute, .{col});

    context.state.rowOffset = row;
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

pub fn resetStyles(writer: *Writer) !void {
    try writer.writeAll(codes.resetStyles);
}

pub fn setCursorPosAbsolute(row: usize, col: usize, writer: *Writer) !void {
    try writer.print(codes.setCursorPosAbsolute, .{ row, col });
}

pub fn boldText(writer: *Writer) !void {
    try writer.writeAll(codes.boldText);
}

pub fn disableBoldText(writer: *Writer) !void {
    try writer.writeAll(codes.disableBoldText);
}

pub fn underlineText(writer: *Writer) !void {
    try writer.writeAll(codes.underlineText);
}

pub fn disableUnderlineText(writer: *Writer) !void {
    try writer.writeAll(codes.disableUnderlineText);
}

pub fn italicText(writer: *Writer) !void {
    try writer.writeAll(codes.italicText);
}

pub fn disableItalicText(writer: *Writer) !void {
    try writer.writeAll(codes.disableItalicText);
}

pub fn moveCursorUp(amount: usize, writer: *Writer) !void {
    try writer.print(codes.moveCursorUp, .{amount});
}

pub fn moveCursorDown(amount: usize, writer: *Writer) !void {
    try writer.print(codes.moveCursorDown, .{amount});
}

pub fn setFgFromColor(color: stylesMod.Color, writer: *Writer) !void {
    const code = switch (color) {
        .Black => "\x1b[30m",
        .Red => "\x1b[31m",
        .Green => "\x1b[32m",
        .Yellow => "\x1b[33m",
        .Blue => "\x1b[34m",
        .Magenta => "\x1b[35m",
        .Cyan => "\x1b[36m",
        .White => "\x1b[37m",
        .None => "\x1b[39m",
    };
    try writer.writeAll(code);
}

pub fn setBgFromColor(color: stylesMod.Color, writer: *Writer) !void {
    const code = switch (color) {
        .Black => "\x1b[40m",
        .Red => "\x1b[41m",
        .Green => "\x1b[42m",
        .Yellow => "\x1b[43m",
        .Blue => "\x1b[44m",
        .Magenta => "\x1b[45m",
        .Cyan => "\x1b[46m",
        .White => "\x1b[47m",
        .None => "\x1b[49m",
    };
    try writer.writeAll(code);
}
