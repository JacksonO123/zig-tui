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

pub const BackBuffer = struct {
    const Self = @This();

    buffer: bufferUtil.CharBuffer,
    lineLimit: usize,
    rendering: stylesMod.SimpleDataStyle = .{},

    pub inline fn init(
        allocator: Allocator,
        size: utils.Size,
    ) !Self {
        var lines: bufferUtil.CharBuffer = .empty;
        const line = try bufferUtil.createLine(allocator, size.width);
        try lines.append(allocator, line);

        return .{
            .buffer = lines,
            .lineLimit = 1,
        };
    }

    pub fn reset(
        self: *Self,
        allocator: Allocator,
        size: utils.Size,
    ) !void {
        for (self.buffer.items) |*line| {
            try bufferUtil.prepareLineBuffer(allocator, line, size.width, .All);
        }

        self.lineLimit = 1;
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
        element: *ui.UIElement,
        size: utils.Size,
    ) !void {
        const preAdjust = ui.getPreAdjustment(element.styles);
        const postAdjust = ui.getPostAdjustment(element.styles);
        const simpleStyles = element.styles.toSimpleStyles();

        {
            try self.ensureLineExists(allocator, element.layoutInfo.y + element.layoutInfo.height, size.width);
            var styleCpy = simpleStyles;
            styleCpy.underline = false;
            for (self.buffer.items[element.layoutInfo.y .. element.layoutInfo.y + element.layoutInfo.height]) |line| {
                if (element.layoutInfo.x < size.width) {
                    const to = @min(element.layoutInfo.x + element.layoutInfo.width, size.width);
                    @memset(line.items[element.layoutInfo.x..to], .{
                        .data = .{
                            .bytes = "    ".*,
                            .len = 1,
                        },
                        .style = styleCpy,
                    });
                }
            }
        }

        switch (element.variant) {
            .Text => |text| {
                var renderPos = utils.Pos{
                    .x = element.layoutInfo.x + preAdjust.width,
                    .y = element.layoutInfo.y + preAdjust.height,
                };

                var currentHeight = preAdjust.height + postAdjust.height;
                var currentWidth = preAdjust.width + postAdjust.width;

                var i: usize = 0;
                while (i < text.data.len) : (i += 1) {
                    const char = text.data[i];

                    if (char == '\n') {
                        if (currentHeight >= element.layoutInfo.height) {
                            break;
                        }

                        renderPos.x = element.layoutInfo.x + preAdjust.width;
                        currentWidth = 0;
                        renderPos.y += 1;
                        currentHeight += 1;
                        continue;
                    }

                    if (currentWidth >= element.layoutInfo.width) {
                        while (i < text.data.len and text.data[i] != '\n') : (i += 1) {}

                        if (i >= text.data.len or text.data[i] != '\n') break;

                        if (currentHeight >= element.layoutInfo.height) {
                            break;
                        }

                        renderPos.x = element.layoutInfo.x + preAdjust.width;
                        currentWidth = 0;
                        renderPos.y += 1;
                        currentHeight += 1;
                        continue;
                    }

                    try self.writeCharAtPos(allocator, size, renderPos, char, simpleStyles);
                    renderPos.x += 1;
                    currentWidth += 1;
                }
            },
            .Layout => |layout| {
                switch (layout) {
                    .Horizontal => |layoutUtil| {
                        for (layoutUtil.elements) |el| {
                            try self.renderInBuffer(allocator, el, size);
                        }
                    },
                    .Vertical => |layoutUtil| {
                        for (layoutUtil.elements) |el| {
                            try self.renderInBuffer(allocator, el, size);
                        }
                    },
                }
            },
        }

        try self.ensureLineExists(
            allocator,
            element.layoutInfo.y + element.layoutInfo.height,
            size.width,
        );
        try self.renderStylesPost(allocator, element.layoutInfo, element.styles, size);
    }

    fn renderStylesPost(
        self: *Self,
        allocator: Allocator,
        layoutInfo: ui.ElementLayoutInfo,
        styles: stylesMod.Styles,
        size: utils.Size,
    ) !void {
        var pos = utils.Pos{
            .x = layoutInfo.x,
            .y = layoutInfo.y,
        };
        if (styles.styles.border.getChars()) |borderStyles| {
            var simpleStyles = styles.toSimpleStyles();
            simpleStyles.underline = false;

            try self.writeUnicodeAtPos(
                allocator,
                size,
                pos,
                borderStyles.corners.topLeft,
                simpleStyles,
            );

            pos.x = layoutInfo.x + layoutInfo.width - 1;
            try self.writeUnicodeAtPos(
                allocator,
                size,
                pos,
                borderStyles.corners.topRight,
                simpleStyles,
            );

            pos.x = layoutInfo.x;
            pos.y = layoutInfo.y + layoutInfo.height - 1;
            try self.writeUnicodeAtPos(
                allocator,
                size,
                pos,
                borderStyles.corners.bottomLeft,
                simpleStyles,
            );

            pos.x = layoutInfo.x + layoutInfo.width - 1;
            try self.writeUnicodeAtPos(
                allocator,
                size,
                pos,
                borderStyles.corners.bottomRight,
                simpleStyles,
            );

            var horizontalBorder = bufferUtil.BufferChar{
                .style = simpleStyles,
                .data = .{
                    .bytes = "    ".*,
                    .len = 0,
                },
            };
            @memcpy(
                horizontalBorder.data.bytes[0..borderStyles.horizontal.len],
                borderStyles.horizontal,
            );
            horizontalBorder.data.len = @intCast(borderStyles.horizontal.len);

            var verticalBorder = bufferUtil.BufferChar{
                .style = simpleStyles,
                .data = .{
                    .bytes = "    ".*,
                    .len = 0,
                },
            };
            @memcpy(
                verticalBorder.data.bytes[0..borderStyles.vertical.len],
                borderStyles.vertical,
            );
            verticalBorder.data.len = @intCast(borderStyles.vertical.len);

            a: {
                const line = &self.buffer.items[layoutInfo.y];
                if (layoutInfo.x + 1 >= line.items.len) break :a;
                const cells = line.items[layoutInfo.x + 1 .. @min(
                    layoutInfo.x + layoutInfo.width - 1,
                    line.items.len,
                )];
                @memset(cells, horizontalBorder);
            }

            a: {
                const line = &self.buffer.items[layoutInfo.y + layoutInfo.height - 1];
                if (layoutInfo.x + 1 >= line.items.len) break :a;
                const cells = line.items[layoutInfo.x + 1 .. @min(
                    layoutInfo.x + layoutInfo.width - 1,
                    line.items.len,
                )];
                @memset(cells, horizontalBorder);
            }

            var currentY: usize = layoutInfo.y + 1;
            const endY = layoutInfo.y + layoutInfo.height - 1;
            while (currentY < endY) : (currentY += 1) {
                const line = self.buffer.items[currentY];
                if (layoutInfo.x >= line.items.len) break;
                const leftCell = &line.items[layoutInfo.x];
                leftCell.* = verticalBorder;

                if (layoutInfo.x + layoutInfo.width - 1 >= line.items.len) continue;
                const rightCell = &line.items[layoutInfo.x + layoutInfo.width - 1];
                rightCell.* = verticalBorder;
            }
        }
    }

    fn writeCharAtPos(
        self: *Self,
        allocator: Allocator,
        size: utils.Size,
        pos: utils.Pos,
        char: u8,
        styles: stylesMod.SimpleDataStyle,
    ) !void {
        try self.ensureLineExists(allocator, pos.y, size.width);
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
        size: utils.Size,
        pos: utils.Pos,
        chars: []const u8,
        styles: stylesMod.SimpleDataStyle,
    ) !void {
        try self.ensureLineExists(allocator, pos.y, size.width);
        const line = self.buffer.items[pos.y];
        if (pos.x >= line.items.len) return;
        var cell = &line.items[pos.x];

        @memcpy(cell.data.bytes[0..chars.len], chars);
        cell.data.len = @intCast(chars.len);
        cell.style = styles;
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
