const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const sequences = @import("sequences.zig");
const stylesMod = @import("styles.zig");
const terminalUtils = @import("terminal_utils.zig");
const termMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const globalState = &@import("global.zig").globalState;

pub fn RenderUIFn(comptime ModelType: type) type {
    return fn (*termMod.Terminal(ModelType)) anyerror!*ui.UIElement;
}

pub fn handleRender(
    comptime ModelType: type,
    gpa: Allocator,
    context: *RenderContext(ModelType, void),
    renderUI: RenderUIFn(ModelType),
    writer: *Writer,
) !void {
    const success = try context.terminalUtils.prepareForReRender(writer);
    if (!success) return;
    context.rendered = null;

    globalState.rendering = true;
    defer globalState.rendering = false;

    const el = try renderUI(context.terminal);
    context.rendered = el;
    try render(gpa, @ptrCast(context), el, writer);
}

pub fn render(
    allocator: Allocator,
    context: *RenderContext(anyopaque, void),
    el: *ui.UIElement,
    writer: *Writer,
) !void {
    if (context.config.screenType == .Alternate) {
        try sequences.setCursorPosAbsolute(context, 1, 1, writer);
    } else {
        try sequences.setCursorPos(context, 1, 1, writer);
    }

    if (context.state.forceFullRender) {
        try sequences.eraseDisplayAfterCursor(writer);
    }

    try context.backBuffer.reset(allocator, context.terminalUtils.size);
    {
        var termSizeCopy = context.terminalUtils.size;
        const rightPadding = terminalUtils.calculateRightPadding(context.config);
        termSizeCopy.width -= rightPadding;

        try ui.setElementDimensions(
            context.terminalUtils.renderArena.allocator(),
            context,
            el,
            termSizeCopy,
            .{},
            .{},
        );
    }
    try context.backBuffer.renderInBuffer(allocator, el, context.terminalUtils.size);
    try writeDiff(allocator, context, context.terminalUtils.size, writer);

    try sequences.resetStyles(writer);
    context.backBuffer.rendering = .{};
    context.frontBuffer.rendering = .{};

    context.state.rowOffset = @intCast(context.backBuffer.lineLimit);

    if (context.config.screenType == .Main) {
        try sequences.setCursorPos(context, 1, 1, writer);
    }

    context.state.forceFullRender = false;

    try writer.flush();
}

fn writeDiff(
    allocator: Allocator,
    context: *contextMod.RenderContext(anyopaque, void),
    size: utils.Size,
    writer: *Writer,
) !void {
    try context.frontBuffer.matchSize(allocator, context.backBuffer.lineLimit, size.width);

    var atCol: usize = 0;
    const frontBufferLines = context.frontBuffer.buffer.items[0..context.frontBuffer.lineLimit];
    const backBufferLines = context.backBuffer.buffer.items[0..context.backBuffer.lineLimit];
    const rightPadding = terminalUtils.calculateRightPadding(context.config);
    for (frontBufferLines, backBufferLines, 0..) |frontLine, backLine, rowIndex| {
        for (frontLine.items, backLine.items, 0..) |frontCell, backCell, cellIndex| {
            if (cellIndex >= size.width - rightPadding) break;

            if (context.state.forceFullRender or !frontCell.compareTo(backCell)) {
                if (atCol < cellIndex) {
                    try sequences.setCursorCol(@intCast(cellIndex + 1), writer);
                }

                try matchRenderStyle(&context.frontBuffer.rendering, backCell.style, writer);
                try writer.writeAll(backCell.data.bytes[0..backCell.data.len]);

                atCol += 1;
            }
        }

        @memcpy(frontLine.items, backLine.items);

        try sequences.setBgFromColor(.None, writer);
        context.frontBuffer.rendering.bg = .None;

        if (rowIndex + 1 < frontBufferLines.len) {
            try sequences.simulateNewline(context, writer);
        } else {
            switch (context.config.screenType) {
                .Alternate => {
                    try sequences.setCursorPosAbsolute(
                        context,
                        @intCast(context.backBuffer.lineLimit + 1),
                        1,
                        writer,
                    );
                    try sequences.eraseDisplayAfterCursor(writer);
                },
                .Main => {
                    try sequences.setCursorCol(context.terminalUtils.size.width + 1, writer);
                    try sequences.eraseDisplayAfterCursor(writer);
                },
            }
        }

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

    if (std.meta.activeTag(rendering.fg) != std.meta.activeTag(styles.fg)) {
        try sequences.setFgFromColor(styles.fg, writer);
        rendering.fg = styles.fg;
    }

    if (std.meta.activeTag(rendering.bg) != std.meta.activeTag(styles.bg)) {
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
