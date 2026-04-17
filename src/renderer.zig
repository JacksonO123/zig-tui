const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const utils = @import("utils.zig");

pub fn render(childAllocator: Allocator, size: utils.WinSize, writer: *Writer) !void {
    // try writer.writeAll("\x1b[2J\x1b[H");
}
