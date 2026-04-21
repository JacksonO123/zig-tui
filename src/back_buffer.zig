const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const configMod = @import("config.zig");
const sequences = @import("sequences.zig");
const stylesMod = @import("styles.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const BackBufferPos = struct {
    x: usize,
    y: usize,
};

const BufferCharVariants = enum {
    Char,
    Unicode,
};

const BufferChar = union(BufferCharVariants) {
    Char: u8,
    Unicode: []const u8,
};

pub const BackBuffer = struct {
    const Self = @This();

    const BackBufferLine = std.ArrayList(BufferChar);
    const BufferLines = std.ArrayList(BackBufferLine);

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

    inline fn createLine(allocator: Allocator, size: utils.WinSize) !BackBufferLine {
        var line = try BackBufferLine.initCapacity(allocator, size.col);
        line.items.len = size.col;
        @memset(line.items, .{ .Char = ' ' });
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
        const trueStart = self.pos;

        self.renderStylesPreAdjust(element.styles);

        const startPos = self.pos;

        switch (element.variant) {
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

        try self.renderStylesPost(allocator, trueStart, element.styles, size);
    }

    fn renderStylesPreAdjust(self: *Self, styles: stylesMod.Styles) void {
        if (styles.styles.border != null) {
            self.pos.x += 1;
            self.pos.y += 1;
        }
    }

    fn renderStylesPostAdjust(self: *Self, styles: stylesMod.Styles) void {
        if (styles.styles.border != null) {
            self.pos.x += 1;
            self.pos.y += 1;
        }
    }

    fn renderStylesPost(
        self: *Self,
        allocator: Allocator,
        start: BackBufferPos,
        styles: stylesMod.Styles,
        size: utils.WinSize,
    ) !void {
        self.renderStylesPostAdjust(styles);

        var pos = start;
        if (styles.styles.border) |borderStyles| {
            try self.writeUnicodeAtPos(allocator, size, pos, borderStyles.corners.topLeft);
            pos.x = self.pos.x - 1;
            try self.writeUnicodeAtPos(allocator, size, pos, borderStyles.corners.topRight);
            pos.x = start.x;
            pos.y = self.pos.y;
            try self.writeUnicodeAtPos(allocator, size, pos, borderStyles.corners.bottomLeft);
            pos.x = self.pos.x - 1;
            try self.writeUnicodeAtPos(allocator, size, pos, borderStyles.corners.bottomRight);
            pos.y = start.y;
            pos.x = start.x + 1;

            const diffX = self.pos.x - pos.x - 1;
            var i: usize = 0;
            while (i < diffX) : (i += 1) {
                const prev = pos.y;

                try self.writeUnicodeAtPos(allocator, size, pos, borderStyles.horizontal);
                pos.y = self.pos.y;
                try self.writeUnicodeAtPos(allocator, size, pos, borderStyles.horizontal);
                pos.y = prev;

                pos.x += 1;
            }

            pos.x = start.x;
            pos.y += 1;

            i = 0;
            const diffY = self.pos.y - pos.y;
            while (i < diffY) : (i += 1) {
                const prev = pos.x;

                try self.writeUnicodeAtPos(allocator, size, pos, borderStyles.vertical);
                pos.x = self.pos.x - 1;
                try self.writeUnicodeAtPos(allocator, size, pos, borderStyles.vertical);
                pos.x = prev;

                pos.y += 1;
            }
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

        self.lines.items[pos.y].items[pos.x] = .{ .Char = char };
    }

    fn writeUnicodeAtPos(
        self: *Self,
        allocator: Allocator,
        size: utils.WinSize,
        pos: BackBufferPos,
        chars: []const u8,
    ) !void {
        while (pos.y >= self.lines.items.len) {
            const line = try BackBuffer.createLine(allocator, size);
            try self.lines.append(allocator, line);
        }

        self.lines.items[pos.y].items[pos.x] = .{ .Unicode = chars };
    }

    pub fn writeToWriter(self: Self, writer: *Writer) !void {
        var col: usize = 0;

        for (self.lines.items) |line| {
            for (line.items) |bufChar| {
                switch (bufChar) {
                    .Char => |char| {
                        try writer.writeByte(char);
                        col += 1;
                    },
                    .Unicode => |char| {
                        try writer.writeAll(char);
                        col += 1;
                        // try sequences.setCursorCol(col + 1, writer);
                    },
                }
            }
            try writer.writeByte('\n');
        }
    }
};
