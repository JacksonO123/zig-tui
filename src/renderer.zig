const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const sequences = @import("sequences.zig");
const stylesMod = @import("styles.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");
const bufferUtil = @import("buffer.zig");

pub fn render(
    allocator: Allocator,
    context: *RenderContext,
    el: *ui.UIElement,
    writer: *Writer,
) !void {
    if (context.config.screenType == .Fullscreen) {
        try sequences.setCursorPosAbsolute(1, 1, writer);
    } else {
        try sequences.setCursorPos(context, 1, 1, writer);
    }

    if (context.state.forceReRender) {
        try sequences.eraseDisplayAfterCursor(writer);
    }

    try context.backBuffer.reset(allocator, context.terminal.size);
    ui.setElementDimensions(el, context.terminal.size, .{});
    try context.backBuffer.renderInBuffer(allocator, el, context.terminal.size);
    try writeDiff(allocator, context, context.terminal.size, writer);

    try sequences.resetStyles(writer);
    context.backBuffer.rendering = .{};
    context.frontBuffer.rendering = .{};
    try sequences.eraseDisplayAfterCursor(writer);

    context.state.rowOffset = @as(i32, @intCast(context.backBuffer.lineLimit)) + 1;
    context.state.forceReRender = false;

    try writer.flush();
}

fn writeDiff(
    allocator: Allocator,
    context: *contextMod.RenderContext,
    size: utils.Size,
    writer: *Writer,
) !void {
    try context.frontBuffer.matchSize(allocator, context.backBuffer.lineLimit, size.width);

    var atCol: usize = 0;
    const frontBufferLines = context.frontBuffer.buffer.items[0..context.frontBuffer.lineLimit];
    const backBufferLines = context.backBuffer.buffer.items[0..context.backBuffer.lineLimit];
    for (frontBufferLines, backBufferLines) |*frontLine, *backLine| {
        for (frontLine.items, backLine.items, 0..) |frontCell, backCell, cellIndex| {
            if (cellIndex >= size.width - 1) break;

            if (context.state.forceReRender or !frontCell.compareTo(backCell)) {
                if (atCol < cellIndex) {
                    try sequences.setCursorCol(cellIndex + 1, writer);
                }

                try matchRenderStyle(&context.frontBuffer.rendering, backCell.style, writer);
                try writer.writeAll(backCell.data.bytes[0..backCell.data.len]);

                atCol += 1;
            }
        }

        @memcpy(frontLine.items, backLine.items);

        try sequences.setBgFromColor(.None, writer);
        context.frontBuffer.rendering.bg = .None;
        try writer.writeAll("\r\n");
        atCol = 0;
    }
}

pub fn matchRenderStyle(
    rendering: *stylesMod.SimpleDataStyle,
    styles: stylesMod.SimpleDataStyle,
    writer: *Writer,
) !void {
    try updateSpecificRenderStyle(
        &rendering.bold,
        styles.bold,
        sequences.boldText,
        sequences.disableBoldText,
        writer,
    );

    try updateSpecificRenderStyle(
        &rendering.underline,
        styles.underline,
        sequences.underlineText,
        sequences.disableUnderlineText,
        writer,
    );

    try updateSpecificRenderStyle(
        &rendering.italic,
        styles.italic,
        sequences.italicText,
        sequences.disableItalicText,
        writer,
    );

    if (rendering.fg != styles.fg) {
        try sequences.setFgFromColor(styles.fg, writer);
        rendering.fg = styles.fg;
    }

    if (rendering.bg != styles.bg) {
        try sequences.setBgFromColor(styles.bg, writer);
        rendering.bg = styles.bg;
    }
}

pub fn updateSpecificRenderStyle(
    cond1: *bool,
    cond2: bool,
    enableFn: fn (*Writer) anyerror!void,
    disableFn: fn (*Writer) anyerror!void,
    writer: *Writer,
) !void {
    if (cond1.* != cond2) {
        if (cond2) try enableFn(writer) else try disableFn(writer);
        cond1.* = cond2;
    }
}
