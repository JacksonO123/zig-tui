const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const sequences = @import("sequences.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn render(
    allocator: Allocator,
    context: *RenderContext,
    el: ui.UIElement,
    size: utils.WinSize,
    writer: *Writer,
) !void {
    if (context.config.fullscreen) {
        try sequences.clearScreen(writer);
    }

    // try sequences.setCursorPos(context, 1, 1, writer);
    // try sequences.eraseDisplayAfterCursor(writer);
    context.backBuffer.pos = .{ .x = 0, .y = 0 };

    try context.backBuffer.renderInBuffer(allocator, el, size);
    try context.backBuffer.writeToWriter(writer);
    try writer.flush();
}
