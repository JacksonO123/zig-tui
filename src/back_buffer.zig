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
        size: utils.Size,
    ) !Self {
        var lines: bufferUtil.CharBuffer = .empty;
        const line = try bufferUtil.createLine(allocator, size.width);
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
        size: utils.Size,
    ) !void {
        for (self.buffer.items) |*line| {
            try bufferUtil.prepareLineBuffer(allocator, line, size.width, .All);
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
        size: utils.Size,
    ) !void {
        const trueStart = self.pos;

        const preAdjust = getPreAdjustment(element.styles);
        const postAdjust = getPostAdjustment(element.styles);
        self.pos.x += preAdjust.width;
        self.pos.y += preAdjust.height;

        const startPos = self.pos;
        const simpleStyles = element.styles.toSimpleStyles();

        const elSize = getElementDimensions(element);

        {
            try self.ensureLineExists(allocator, trueStart.y + elSize.height, size.width);
            var styleCpy = simpleStyles;
            styleCpy.underline = false;
            for (self.buffer.items[trueStart.y .. trueStart.y + elSize.height]) |line| {
                if (trueStart.x < size.width) {
                    const to = @min(trueStart.x + elSize.width, size.width);
                    @memset(line.items[trueStart.x..to], .{
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
                        var maxX = startPos.x;
                        for (elements, 0..) |el, index| {
                            try self.renderInBuffer(allocator, el, size);
                            maxX = @max(maxX, self.pos.x);

                            if (index < elements.len - 1) {
                                self.pos.y += 1;
                                self.pos.x = startPos.x;
                            } else {
                                self.pos.x = maxX;
                            }
                        }
                    },
                }
            },
        }

        self.pos.x += postAdjust.width;
        self.pos.y += postAdjust.height;
        try self.ensureLineExists(allocator, self.pos.y, size.width);
        try self.renderStylesPost(allocator, trueStart, element.styles, size);
    }

    fn renderStylesPost(
        self: *Self,
        allocator: Allocator,
        startPos: BackBufferPos,
        styles: stylesMod.Styles,
        size: utils.Size,
    ) !void {
        var pos = startPos;
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
            pos.x = self.pos.x - 1;
            try self.writeUnicodeAtPos(
                allocator,
                size,
                pos,
                borderStyles.corners.topRight,
                simpleStyles,
            );
            pos.x = startPos.x;
            pos.y = self.pos.y;
            try self.writeUnicodeAtPos(
                allocator,
                size,
                pos,
                borderStyles.corners.bottomLeft,
                simpleStyles,
            );
            pos.x = self.pos.x - 1;
            try self.writeUnicodeAtPos(
                allocator,
                size,
                pos,
                borderStyles.corners.bottomRight,
                simpleStyles,
            );
            pos.y = startPos.y;
            pos.x = startPos.x + 1;

            const diffX = self.pos.x - pos.x - 1;
            var i: usize = 0;
            while (i < diffX) : (i += 1) {
                const prev = pos.y;

                try self.writeUnicodeAtPos(
                    allocator,
                    size,
                    pos,
                    borderStyles.horizontal,
                    simpleStyles,
                );
                pos.y = self.pos.y;
                try self.writeUnicodeAtPos(
                    allocator,
                    size,
                    pos,
                    borderStyles.horizontal,
                    simpleStyles,
                );
                pos.y = prev;

                pos.x += 1;
            }

            pos.x = startPos.x;
            pos.y += 1;

            i = 0;
            const diffY = self.pos.y - pos.y;
            while (i < diffY) : (i += 1) {
                const prev = pos.x;

                try self.writeUnicodeAtPos(
                    allocator,
                    size,
                    pos,
                    borderStyles.vertical,
                    simpleStyles,
                );
                pos.x = self.pos.x - 1;
                try self.writeUnicodeAtPos(
                    allocator,
                    size,
                    pos,
                    borderStyles.vertical,
                    simpleStyles,
                );
                pos.x = prev;

                pos.y += 1;
            }
        }
    }

    fn writeCharAtPos(
        self: *Self,
        allocator: Allocator,
        size: utils.Size,
        pos: BackBufferPos,
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
        pos: BackBufferPos,
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

fn getElementDimensions(element: ui.UIElement) utils.Size {
    var size: utils.Size = .{ .height = 1 };

    const preAdjust = getPreAdjustment(element.styles);
    const postAdjust = getPostAdjustment(element.styles);

    switch (element.variant) {
        .Text => |text| {
            var currentX: u16 = 0;
            for (text.data) |char| {
                if (char == '\n') {
                    size.height += 1;
                    currentX = 0;
                    continue;
                }

                currentX += 1;
                size.width = @max(size.width, currentX);
            }

            size.width += preAdjust.width + postAdjust.width;
            size.height += preAdjust.height + postAdjust.height;
        },
        .Layout => |layout| {
            size.width += preAdjust.width + postAdjust.width;
            size.height += preAdjust.height + postAdjust.height;

            switch (layout) {
                .Horizontal => |elements| {
                    for (elements) |el| {
                        const elSize = getElementDimensions(el);
                        size.width += elSize.width;
                        size.height = @max(size.height, elSize.height);
                    }
                },
                .Vertical => |elements| {
                    if (elements.len > 0) {
                        size.height = 0;
                    }

                    for (elements) |el| {
                        const elSize = getElementDimensions(el);
                        size.height += elSize.height;
                        size.width = @max(size.width, elSize.width);
                    }
                },
            }
        },
    }

    return size;
}

fn getPreAdjustment(styles: stylesMod.Styles) utils.Size {
    var adjustment: utils.Size = .{};

    if (styles.hasBorder()) {
        adjustment.width += 1;
        adjustment.height += 1;
    }

    adjustment.width += styles.styles.padding.paddingLeft;
    adjustment.height += styles.styles.padding.paddingTop;

    return adjustment;
}

fn getPostAdjustment(styles: stylesMod.Styles) utils.Size {
    var adjustment: utils.Size = .{};

    if (styles.hasBorder()) {
        adjustment.width += 1;
        adjustment.height += 1;
    }

    adjustment.width += styles.styles.padding.paddingRight;
    adjustment.height += styles.styles.padding.paddingBottom;

    return adjustment;
}
