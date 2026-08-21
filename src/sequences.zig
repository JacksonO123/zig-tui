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
    hideCursor: Str,
    showCursor: Str,
    requestCursorPosition: Str,

    boldText: Str,
    disableBoldText: Str,

    underlineText: Str,
    disableUnderlineText: Str,

    italicText: Str,
    disableItalicText: Str,

    enableAlternateScreen: Str,
    disableAlternateScreen: Str,
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
    .hideCursor = "\x1b[?25l",
    .showCursor = "\x1b[?25h",
    .requestCursorPosition = "\x1b[6n",

    .boldText = "\x1b[1m",
    .disableBoldText = "\x1b[22m",

    .underlineText = "\x1b[4m",
    .disableUnderlineText = "\x1b[24m",

    .italicText = "\x1b[3m",
    .disableItalicText = "\x1b[23m",

    .enableAlternateScreen = "\x1b[?1049h",
    .disableAlternateScreen = "\x1b[?1049l",
};

pub fn setCursorPos(
    context: *RenderContext(anyopaque),
    row: u16,
    col: u16,
    writer: *Writer,
) !void {
    if (row < context.state.rowOffset) {
        try writer.print(
            codes.moveCursorUp,
            .{@as(i32, @intCast(context.state.rowOffset - row))},
        );
    } else if (row != context.state.rowOffset) {
        try writer.print(codes.moveCursorDown, .{row - context.state.rowOffset});
    }
    try writer.print(codes.setCursorColAbsolute, .{col});

    context.state.rowOffset = row;
}

pub fn setCursorCol(col: u16, writer: *Writer) !void {
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

pub fn setCursorPosAbsolute(
    context: *RenderContext(anyopaque),
    row: u16,
    col: u16,
    writer: *Writer,
) !void {
    try writer.print(codes.setCursorPosAbsolute, .{ row, col });
    context.state.rowOffset = row;
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

pub fn moveCursorUp(
    context: *RenderContext(anyopaque),
    amount: u16,
    writer: *Writer,
) !void {
    const moveAmount = if (context.state.rowOffset -| amount == 0)
        amount - context.state.rowOffset
    else
        amount;

    try writer.print(codes.moveCursorUp, .{moveAmount});
    context.state.rowOffset -= moveAmount;
}

pub fn moveCursorDown(
    context: *RenderContext(anyopaque),
    amount: u16,
    writer: *Writer,
) !void {
    try writer.print(codes.moveCursorDown, .{amount});
    context.state.rowOffset += amount;
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

pub fn hideCursor(writer: *Writer) !void {
    try writer.writeAll(codes.hideCursor);
}

pub fn showCursor(writer: *Writer) !void {
    try writer.writeAll(codes.showCursor);
}

pub fn enableAlternateScreen(writer: *Writer) !void {
    try writer.writeAll(codes.enableAlternateScreen);
}

pub fn disableAlternateScreen(writer: *Writer) !void {
    try writer.writeAll(codes.disableAlternateScreen);
}

pub fn simulateNewline(
    context: *RenderContext(anyopaque),
    writer: *Writer,
) !void {
    switch (context.config.screenType) {
        .Main => {
            try writer.writeAll("\r\n");
            context.state.rowOffset += 1;
        },
        .Alternate => try setCursorPosAbsolute(
            context,
            context.state.rowOffset + 1,
            1,
            writer,
        ),
    }
}

pub fn requestCursorPosition(writer: *Writer) !void {
    try writer.writeAll(codes.requestCursorPosition);
}
