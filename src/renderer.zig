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
    _ = first;
    if (context.config.fullscreen) {
        try sequences.clearScreen(writer);
    }

    try sequences.setCursorPos(context, 1, 1, writer);
    context.backBuffer.pos = .{ .x = 0, .y = 0 };

    try context.backBuffer.renderInBuffer(allocator, el, size);
    context.state.rowOffset = @intCast(context.backBuffer.pos.y);
    try context.backBuffer.writeToWriter(size, writer);
    // try writeDiff(allocator, context, size, writer, first);

    context.state.forceReRender = false;

    try writer.flush();
}

fn writeDiff(
    allocator: Allocator,
    context: *contextMod.RenderContext,
    size: utils.WinSize,
    writer: *Writer,
    first: bool,
) !void {
    _ = first;
    _ = allocator;
    // var toLen: usize = self.buffer.items.len;

    // if (backBuffer.buffer.items.len < self.buffer.items.len) {
    //     self.buffer.items.len = backBuffer.buffer.items.len;
    //     toLen = self.buffer.items.len;
    // } else if (backBuffer.buffer.items.len > self.buffer.items.len) {
    //     const slice = backBuffer.buffer.items[self.buffer.items.len..];
    //     try self.buffer.appendSlice(allocator, slice);
    // }

    for (context.backBuffer.buffer.items, 0..) |char, i| {
        try matchRenderStyle(&context.frontBuffer.rendering, char.style, writer);
        // if (first) {
        //     try writer.writeAll(char.data.bytes[0..char.data.len]);
        // } else {
        try writer.writeByte('@');
        // }

        if ((i + 1) % size.col == 0) {
            try writer.writeByte('\n');
            context.state.rowOffset += 1;
        }
    }

    // var i: usize = 0;
    // var colAt: usize = 0;
    // while (i < toLen) : (i += 1) {
    //     if (state.forceReRender or
    //         !self.buffer.items[i].compareTo(backBuffer.buffer.items[i]))
    //     {
    //         if (colAt < i) {
    //             try sequences.setCursorCol(i, writer);
    //         }

    //         const item = backBuffer.buffer.items[i];
    //         try self.matchRenderStyle(item.style, writer);
    //         try writer.writeAll(item.data.bytes[0..item.data.len]);

    //         colAt += 1;
    //     }

    //     if ((i + 1) % size.col == 0) {
    //         try writer.writeByte('\n');
    //         colAt = 0;
    //     }
    // }

    // i = toLen;
    // while (i < self.buffer.items.len) : (i += 1) {
    //     const item = self.buffer.items[i];
    //     try self.matchRenderStyle(item.style, writer);
    //     try writer.writeAll(item.data.bytes[0..item.data.len]);

    //     colAt += 1;

    //     if ((i + 1) % size.col == 0) {
    //         try writer.writeByte('\n');
    //         colAt = 0;
    //     }
    // }
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
