const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const configMod = @import("config.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const BackBufferPos = struct {
    x: usize,
    y: usize,
};

pub const BackBuffer = struct {
    const Self = @This();

    const BufferLines = std.ArrayList(std.ArrayList(u8));

    lines: BufferLines,
    pos: BackBufferPos,

    pub inline fn initFromConfig(
        allocator: Allocator,
        config: configMod.Config,
        size: utils.WinSize,
    ) !Self {
        const lineSize = if (config.fullscreen) size.row - 1 else @as(u16, 1);
        var lines = try BufferLines.initCapacity(allocator, lineSize);

        var i: usize = 0;
        while (i < lineSize) : (i += 1) {
            const line = try BackBuffer.createLine(allocator, size);
            try lines.append(allocator, line);
        }

        return .{
            .lines = lines,
            .pos = .{
                .x = 0,
                .y = 0,
            },
        };
    }

    inline fn createLine(allocator: Allocator, size: utils.WinSize) !std.ArrayList(u8) {
        var line = try std.ArrayList(u8).initCapacity(allocator, size.col);
        line.items.len = size.col;
        @memset(line.items, ' ');
        return line;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        for (self.lines.items) |line| {
            line.deinit(allocator);
        }
    }

    pub fn renderInBuffer(
        self: *Self,
        allocator: Allocator,
        element: ui.UIElement,
        size: utils.WinSize,
    ) !void {
        const startPos = self.pos;

        switch (element) {
            .Text => |text| {
                var maxWidth: usize = 0;
                for (text.data) |char| {
                    if (char == '\n') {
                        self.pos.x = startPos.x;
                        self.pos.y += 1;
                        continue;
                    }

                    try self.writeCharAtPos(allocator, size, self.pos, char);
                    self.pos.x += 1;
                    maxWidth = @max(maxWidth, self.pos.x);
                }
                self.pos.x = maxWidth;
            },
            .Layout => |layout| {
                switch (layout) {
                    .Horizontal => |elements| {
                        for (elements) |el| {
                            try self.renderInBuffer(allocator, el, size);
                            self.pos.y = startPos.y;
                        }
                    },
                    .Vertical => |elements| {
                        for (elements) |el| {
                            try self.renderInBuffer(allocator, el, size);
                            self.pos.y += 1;
                            self.pos.x = startPos.x;
                        }
                    },
                }
            },
        }
    }

    fn writeCharAtPos(
        self: *Self,
        allocator: Allocator,
        size: utils.WinSize,
        pos: BackBufferPos,
        char: u8,
    ) !void {
        while (pos.y >= self.lines.items.len) {
            const line = try BackBuffer.createLine(allocator, size);
            try self.lines.append(allocator, line);
        }

        self.lines.items[pos.y].items[pos.x] = char;
    }

    pub fn writeToWriter(self: Self, writer: *Writer) !void {
        for (self.lines.items) |line| {
            try writer.writeAll(line.items);
            try writer.writeByte('\n');
        }
    }
};
