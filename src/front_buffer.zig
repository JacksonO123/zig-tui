const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const bufferUtil = @import("buffer.zig");
const stylesMod = @import("styles.zig");

pub const FrontBuffer = struct {
    const Self = @This();

    buffer: std.ArrayList(bufferUtil.BufferLine) = .empty,
    lineLimit: usize = 0,
    rendering: stylesMod.SimpleDataStyle = .{},

    pub const empty: Self = .{};

    pub fn deinit(self: *Self, allocator: Allocator) void {
        for (self.buffer.items) |*line| {
            line.deinit(allocator);
        }

        self.buffer.deinit(allocator);
    }

    pub fn matchSize(
        self: *Self,
        allocator: Allocator,
        lineLimit: usize,
        width: usize,
    ) !void {
        while (self.buffer.items.len < lineLimit) {
            const line = try bufferUtil.createLine(allocator, width);
            try self.buffer.append(allocator, line);
        }

        self.lineLimit = lineLimit;

        for (self.buffer.items[self.lineLimit..]) |*line| {
            try bufferUtil.prepareLineBuffer(allocator, line, width, .All);
        }

        for (self.buffer.items[0..self.lineLimit]) |*line| {
            try bufferUtil.prepareLineBuffer(allocator, line, width, .New);
        }
    }
};
