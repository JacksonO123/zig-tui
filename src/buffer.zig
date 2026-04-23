const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const backBufferMod = @import("back_buffer.zig");
const renderer = @import("renderer.zig");
const sequences = @import("sequences.zig");
const stylesMod = @import("styles.zig");

pub const BufferChar = struct {
    const Self = @This();

    style: stylesMod.SimpleDataStyle = .{},
    data: struct {
        bytes: [4]u8,
        len: u8,
    },

    pub fn compareTo(self: Self, other: Self) bool {
        if (!std.meta.eql(self.style, other.style)) {
            return false;
        }

        if (!std.mem.eql(
            u8,
            self.data.bytes[0..self.data.len],
            other.data.bytes[0..other.data.len],
        )) {
            return false;
        }

        return true;
    }
};

pub const BufferLine = std.ArrayList(BufferChar);

pub const CharBuffer = std.ArrayList(BufferLine);

pub fn ensureBufferCapacity(
    allocator: Allocator,
    buf: *std.ArrayList(BufferChar),
    capacity: usize,
) !void {
    if (capacity <= buf.items.len) return;

    if (capacity > buf.capacity) {
        try buf.ensureTotalCapacity(allocator, capacity);
    }

    const prevLen = buf.items.len;
    buf.items.len = capacity;
    @memset(buf.items[prevLen..], .{ .data = .{ .bytes = "    ".*, .len = 1 } });
}

pub fn createLine(allocator: Allocator, size: usize) !BufferLine {
    var line = try BufferLine.initCapacity(allocator, size);
    line.items.len = size;
    @memset(line.items, .{ .data = .{ .bytes = "    ".*, .len = 1 } });
    return line;
}

pub fn prepareLineBuffer(
    allocator: Allocator,
    line: *BufferLine,
    width: usize,
) !void {
    try line.ensureTotalCapacity(allocator, width);
    line.items.len = width;
    @memset(line.items, .{ .data = .{ .bytes = "    ".*, .len = 1 } });
}

pub fn writeToWriter(
    rendering: *stylesMod.SimpleDataStyle,
    buf: CharBuffer,
    lineLimit: usize,
    writer: *Writer,
) !void {
    rendering.* = .{};
    try sequences.resetStyles(writer);

    for (buf.items[0..lineLimit]) |line| {
        for (line.items) |cell| {
            try renderer.matchRenderStyle(rendering, cell.style, writer);
            try writer.writeAll(cell.data.bytes[0..cell.data.len]);
        }
        try writer.writeByte('\n');
    }
}
