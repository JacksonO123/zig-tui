const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const sequences = @import("sequences.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");
const stylesMod = @import("styles.zig");

pub fn render(
    allocator: Allocator,
    context: *RenderContext,
    el: ui.UIElement,
    size: utils.WinSize,
    writer: *Writer,
    first: bool,
) !void {
    if (context.config.fullscreen) {
        try sequences.clearScreen(writer);
        try sequences.setCursorPosAbsolute(1, 1, writer);
    } else if (!first) {
        if (context.state.rowOffset > 0) {
            try sequences.moveCursorUp(@intCast(context.state.rowOffset), writer);
        }
        try sequences.setCursorCol(1, writer);
        try sequences.eraseDisplayAfterCursor(writer);
    }

    try context.backBuffer.reset(allocator, context.config, size);
    try context.backBuffer.renderInBuffer(allocator, el, size);
    try writeDiff(allocator, context, size, writer);

    context.state.rowOffset = @intCast(context.backBuffer.buffer.items.len / size.col);
    context.state.forceReRender = false;

    try writer.flush();
}

fn writeDiff(
    allocator: Allocator,
    context: *contextMod.RenderContext,
    size: utils.WinSize,
    writer: *Writer,
) !void {
    var toLen: usize = context.frontBuffer.buffer.items.len;

    if (context.backBuffer.buffer.items.len < context.frontBuffer.buffer.items.len) {
        context.frontBuffer.buffer.items.len = context.backBuffer.buffer.items.len;
        toLen = context.frontBuffer.buffer.items.len;
    } else if (context.backBuffer.buffer.items.len > context.frontBuffer.buffer.items.len) {
        const slice = context.backBuffer.buffer.items[context.frontBuffer.buffer.items.len..];
        try context.frontBuffer.buffer.appendSlice(allocator, slice);
    }

    var i: usize = 0;
    var atCol: usize = 0;
    while (i < toLen) : (i += 1) {
        if (context.state.forceReRender or
            !context.frontBuffer.buffer.items[i].compareTo(context.backBuffer.buffer.items[i]))
        {
            if (atCol < i) {
                try sequences.setCursorCol(i + 1, writer);
            }

            const item = context.backBuffer.buffer.items[i];
            try matchRenderStyle(&context.frontBuffer.rendering, item.style, writer);
            try writer.writeAll(item.data.bytes[0..item.data.len]);

            atCol += 1;
        }

        if ((i + 1) % size.col == 0) {
            try writer.writeByte('\n');
        }
    }

    i = toLen;
    while (i < context.frontBuffer.buffer.items.len) : (i += 1) {
        const item = context.frontBuffer.buffer.items[i];
        try matchRenderStyle(&context.frontBuffer.rendering, item.style, writer);
        try writer.writeAll(item.data.bytes[0..item.data.len]);

        if ((i + 1) % size.col == 0) {
            try writer.writeByte('\n');
        }
    }

    @memcpy(context.frontBuffer.buffer.items, context.backBuffer.buffer.items);
}

fn matchRenderStyle(
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
