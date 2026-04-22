const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

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

pub const BackBuffer = struct {
    const Self = @This();

    const CharBuffer = std.ArrayList(BufferChar);

    buffer: CharBuffer,
    pos: BackBufferPos,
    rendering: stylesMod.SimpleDataStyle = .{},

    pub inline fn initFromConfig(
        allocator: Allocator,
        config: configMod.Config,
        size: utils.WinSize,
    ) !Self {
        const numLines = if (config.fullscreen) size.row - 1 else @as(u16, 1);
        const numChars = numLines * size.col;
        var lines = try CharBuffer.initCapacity(allocator, numChars);
        lines.items.len = numChars;
        @memset(lines.items, .{ .data = .{ .bytes = "    ".*, .len = 1 } });

        return .{
            .buffer = lines,
            .pos = .{
                .x = 0,
                .y = 0,
            },
        };
    }

    pub fn reset(
        self: *Self,
        allocator: Allocator,
        config: configMod.Config,
        size: utils.WinSize,
    ) !void {
        const numLines = if (config.fullscreen) size.row - 1 else @as(u16, 1);
        const numChars = numLines * size.col;
        try self.buffer.resize(allocator, numChars);
        @memset(self.buffer.items, .{ .data = .{ .bytes = "    ".*, .len = 1 } });
        self.pos = .{ .x = 0, .y = 0 };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        for (self.buffer.items) |line| {
            line.deinit(allocator);
        }

        self.buffer.deinit();
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
                var maxWidth: usize = 0;
                for (text.data) |char| {
                    if (char == '\n') {
                        self.pos.x = startPos.x;
                        self.pos.y += 1;
                        continue;
                    }

                    try self.writeCharAtPos(allocator, size, self.pos, char, simpleStyles);
                    self.pos.x += 1;
                    maxWidth = @max(maxWidth, self.pos.x);
                }
                self.pos.x = maxWidth;
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
        const index = pos.y * size.col + pos.x;
        try utils.ensureBufferCapacity(allocator, &self.buffer, index + 1);

        var cell = &self.buffer.items[index];

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
        const index = pos.y * size.col + pos.x;
        try utils.ensureBufferCapacity(allocator, &self.buffer, index + 1);

        var cell = &self.buffer.items[index];

        @memcpy(cell.data.bytes[0..chars.len], chars);
        cell.data.len = @intCast(chars.len);
    }

    pub fn writeToWriter(self: *Self, size: utils.WinSize, writer: *Writer) !void {
        self.rendering = .{};
        try sequences.resetStyles(writer);
        for (self.buffer.items, 0..) |cell, index| {
            try self.matchRenderStyle(cell.style, writer);
            try writer.writeAll(cell.data.bytes[0..cell.data.len]);

            if ((index + 1) % size.col == 0) {
                try writer.writeByte('\n');
            }
        }
    }

    fn matchRenderStyle(self: *Self, styles: stylesMod.SimpleDataStyle, writer: *Writer) !void {
        try renderer.updateSpecificRenderStyle(
            &self.rendering.bold,
            styles.bold,
            sequences.boldText,
            sequences.disableBoldText,
            writer,
        );

        try renderer.updateSpecificRenderStyle(
            &self.rendering.underline,
            styles.underline,
            sequences.underlineText,
            sequences.disableUnderlineText,
            writer,
        );

        try renderer.updateSpecificRenderStyle(
            &self.rendering.italic,
            styles.italic,
            sequences.italicText,
            sequences.disableItalicText,
            writer,
        );
    }
};
