const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const sequences = @import("sequences.zig");
const utils = @import("utils.zig");

pub fn render(context: *RenderContext, size: utils.WinSize, writer: *Writer) !void {
    if (context.config.fullscreen) {
        try sequences.clearScreen(writer);
    }

    try sequences.setCursorPos(context, 1, 1, writer);
    try sequences.eraseDisplayAfterCursor(writer);

    try renderTermUI(context, size, writer);
    try writer.flush();
}

fn renderTermUI(context: *RenderContext, size: utils.WinSize, writer: *Writer) !void {
    _ = size;

    for (context.terminal.elements.items) |item| {
        switch (item) {
            .Text => |content| {
                try sequences.writeAscii(context, content, writer);
            },
        }
    }
}
