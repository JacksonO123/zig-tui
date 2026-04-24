const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const bufferUtil = @import("buffer.zig");
const configMod = @import("config.zig");
const frontBufferMod = @import("front_buffer.zig");
const renderer = @import("renderer.zig");
const sequences = @import("sequences.zig");
const stylesMod = @import("styles.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const BackBufferPos = struct {
    x: usize,
    y: usize,
};

pub const BackBuffer = struct {
    const Self = @This();

    buffer: bufferUtil.CharBuffer,
    lineLimit: usize,
    pos: BackBufferPos,
    rendering: stylesMod.SimpleDataStyle = .{},

    pub inline fn init(
        allocator: Allocator,
        size: utils.WinSize,
    ) !Self {
        var lines: bufferUtil.CharBuffer = .empty;
        const line = try bufferUtil.createLine(allocator, size.col);
        try lines.append(allocator, line);

        return .{
            .buffer = lines,
            .lineLimit = 1,
            .pos = .{
                .x = 0,
                .y = 0,
            },
        };
    }

    pub fn reset(
        self: *Self,
        allocator: Allocator,
        size: utils.WinSize,
    ) !void {
        for (self.buffer.items) |*line| {
            try bufferUtil.prepareLineBuffer(allocator, line, size.col, .All);
        }

        self.lineLimit = 1;
        self.pos = .{ .x = 0, .y = 0 };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        for (self.buffer.items) |*line| {
            line.deinit(allocator);
        }

        self.buffer.deinit(allocator);
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
        const simpleStyles = element.styles.toSimpleStyles();

        switch (element.variant) {
            .Text => |text| {
                var maxX: usize = self.pos.x;
                for (text.data) |char| {
                    if (char == '\n') {
                        self.pos.x = startPos.x;
                        self.pos.y += 1;
                        continue;
                    }

                    try self.writeCharAtPos(allocator, size, self.pos, char, simpleStyles);
                    self.pos.x += 1;
                    maxX = @max(maxX, self.pos.x);
                }
                self.pos.x = maxX;
            },
            .Layout => |layout| {
                switch (layout) {
                    .Horizontal => |elements| {
                        var maxY = startPos.y;
                        for (elements) |el| {
                            try self.renderInBuffer(allocator, el, size);
                            maxY = @max(maxY, self.pos.y);
                            self.pos.y = startPos.y;
                        }
                        self.pos.y = maxY;
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
        if (styles.hasBorder()) {
            self.pos.x += 1;
            self.pos.y += 1;
        }

        self.pos.x += styles.styles.padding.paddingLeft;
        self.pos.y += styles.styles.padding.paddingTop;
    }

    fn renderStylesPostAdjust(self: *Self, styles: stylesMod.Styles) void {
        if (styles.hasBorder()) {
            self.pos.x += 1;
            self.pos.y += 1;
        }

        self.pos.x += styles.styles.padding.paddingRight;
        self.pos.y += styles.styles.padding.paddingBottom;
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
        if (styles.styles.border.getChars()) |borderStyles| {
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
        styles: stylesMod.SimpleDataStyle,
    ) !void {
        try self.ensureLineExists(allocator, pos.y, size.col);
        const line = self.buffer.items[pos.y];
        if (pos.x >= line.items.len) return;
        var cell = &line.items[pos.x];

        cell.data.bytes[0] = char;
        cell.data.len = 1;
        cell.style = styles;
    }

    fn writeUnicodeAtPos(
        self: *Self,
        allocator: Allocator,
        size: utils.WinSize,
        pos: BackBufferPos,
        chars: []const u8,
    ) !void {
        try self.ensureLineExists(allocator, pos.y, size.col);
        const line = self.buffer.items[pos.y];
        if (pos.x >= line.items.len) return;
        var cell = &line.items[pos.x];

        @memcpy(cell.data.bytes[0..chars.len], chars);
        cell.data.len = @intCast(chars.len);
    }

    fn ensureLineExists(self: *Self, allocator: Allocator, lineIndex: usize, width: usize) !void {
        if (lineIndex < self.buffer.items.len) {
            self.lineLimit = @max(self.lineLimit, lineIndex + 1);
            return;
        }

        while (self.buffer.items.len < lineIndex + 1) {
            const line = try bufferUtil.createLine(allocator, width);
            try self.buffer.append(allocator, line);
        }
        self.lineLimit = lineIndex + 1;
    }
};
