const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const bufferUtil = @import("buffer.zig");
const stylesMod = @import("styles.zig");
const terminalUtils = @import("terminal_utils.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");
const logMod = @import("logger.zig");

pub const BackBuffer = struct {
    const Self = @This();

    buffer: bufferUtil.CharBuffer,
    lineLimit: usize,
    rendering: stylesMod.SimpleDataStyle = .{},

    pub inline fn init(
        gpa: Allocator,
        size: utils.Size,
    ) !Self {
        var lines: bufferUtil.CharBuffer = .empty;
        const line = try bufferUtil.createLine(gpa, size.width);
        try lines.append(gpa, line);

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
        for (self.buffer.items) |line| {
            try bufferUtil.prepareLineBuffer(allocator, line, size.width, .All);
        }

        self.lineLimit = 1;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        for (self.buffer.items) |line| {
            line.deinit(allocator);
            allocator.destroy(line);
        }

        self.buffer.deinit(allocator);
    }

    pub fn renderInBuffer(
        self: *Self,
        allocator: Allocator,
        element: *ui.UIElement,
        size: utils.Size,
        relativeWritePosAcc: utils.Pos,
        absoluteWritePosAcc: utils.Pos,
    ) !void {
        const preAdjust = ui.getPreAdjustment(element.styles);
        const postAdjust = ui.getPostAdjustment(element.styles);
        const simpleStyles = element.styles.toSimpleStyles();

        const newAbsoluteWritePosAcc = if (element.styles.styles.position == .Absolute)
            absoluteWritePosAcc.appendOffset(element.layoutInfo.offsetToPos())
        else if (element.styles.styles.relativeAnchor)
            relativeWritePosAcc.appendOffset(element.layoutInfo.offsetToPos())
        else
            absoluteWritePosAcc;

        const renderPos = if (element.styles.styles.position == .Relative)
            relativeWritePosAcc.appendOffset(element.layoutInfo.offsetToPos())
        else
            newAbsoluteWritePosAcc;

        {
            try self.ensureLineExists(allocator, renderPos.y + element.layoutInfo.height, size.width);
            var styleCpy = simpleStyles;
            styleCpy.underline = false;
            for (self.buffer.items[renderPos.y .. renderPos.y + element.layoutInfo.height], 0..) |line, rowIndex| a: {
                if (renderPos.x >= size.width) break :a;
                const to = @min(renderPos.x + element.layoutInfo.width, size.width);
                @memset(line.items[renderPos.x..to], .{
                    .data = .{
                        .bytes = "    ".*,
                        .len = 1,
                    },
                    .style = styleCpy,
                });

                if (element.styles.styles.cellFn) |cellFn| {
                    for (line.items[renderPos.x..to], 0..) |*cell, colIndex| {
                        if (cellFn(
                            @intCast(colIndex),
                            @intCast(rowIndex),
                            element.layoutInfo.width + preAdjust.width + postAdjust.width,
                            element.layoutInfo.height + preAdjust.height + postAdjust.height,
                        )) |cellStyle| {
                            cell.style = cellStyle;
                        }
                    }
                }
            }
        }

        switch (element.variant) {
            .Text => |text| {
                const basePos = utils.Pos{
                    .x = renderPos.x + preAdjust.width,
                    .y = renderPos.y + preAdjust.height,
                };

                for (text.renderedData, 0..) |line, lineIndex| {
                    const utf8View = try std.unicode.Utf8View.init(line);
                    var charIt = utf8View.iterator();
                    var index: usize = 0;
                    while (charIt.nextCodepointSlice()) |chars| : (index += 1) {
                        const pos = utils.Pos{
                            .x = basePos.x + @as(u16, @intCast(index)),
                            .y = basePos.y + @as(u16, @intCast(lineIndex)),
                        };
                        if (chars.len == 1) {
                            try self.writeCharAtPos(allocator, size, pos, chars[0], simpleStyles);
                        } else {
                            try self.writeUnicodeAtPos(allocator, size, pos, chars, simpleStyles);
                        }
                    }
                }
            },
            .Layout => |layout| {
                for (layout.data.elements) |elOrNull| {
                    const el = elOrNull orelse continue;
                    try self.renderInBuffer(
                        allocator,
                        el,
                        size,
                        renderPos,
                        newAbsoluteWritePosAcc,
                    );
                }
            },
        }

        try self.ensureLineExists(
            allocator,
            renderPos.y + element.layoutInfo.height,
            size.width,
        );
        try self.renderStylesPost(
            allocator,
            element.layoutInfo,
            preAdjust,
            postAdjust,
            renderPos,
            element.styles,
            size,
        );
    }

    fn renderStylesPost(
        self: *Self,
        allocator: Allocator,
        layoutInfo: ui.ElementLayoutInfo,
        preAdjust: utils.Size,
        postAdjust: utils.Size,
        renderPos: utils.Pos,
        styles: stylesMod.Styles,
        size: utils.Size,
    ) !void {
        const cellFn = styles.styles.cellFn;
        const adjustWidth = preAdjust.width + postAdjust.width;
        const adjustHeight = preAdjust.height + postAdjust.height;

        var pos = renderPos;
        if (styles.styles.border.getChars()) |borderStyles| {
            var simpleStyles = styles.toSimpleStyles();
            simpleStyles.underline = false;

            const topLeftCornerStyle = if (cellFn) |func|
                func(0, 0, layoutInfo.width + adjustWidth, layoutInfo.height + adjustHeight) orelse
                    simpleStyles
            else
                simpleStyles;

            try self.writeUnicodeAtPos(
                allocator,
                size,
                pos,
                borderStyles.corners.topLeft,
                topLeftCornerStyle,
            );

            if (layoutInfo.width > 0) {
                pos.x = renderPos.x + layoutInfo.width - 1;
                const topRightCornerStyle = if (cellFn) |func|
                    func(layoutInfo.width - 1, 0, layoutInfo.width + adjustWidth, layoutInfo.height + adjustHeight) orelse
                        simpleStyles
                else
                    simpleStyles;
                try self.writeUnicodeAtPos(
                    allocator,
                    size,
                    pos,
                    borderStyles.corners.topRight,
                    topRightCornerStyle,
                );

                pos.y = renderPos.y + layoutInfo.height - 1;
                pos.x = renderPos.x + layoutInfo.width - 1;
                const bottomRightCornerStyle = if (cellFn) |func|
                    func(
                        layoutInfo.width - 1,
                        layoutInfo.height - 1,
                        layoutInfo.width + adjustWidth,
                        layoutInfo.height + adjustHeight,
                    ) orelse
                        simpleStyles
                else
                    simpleStyles;
                try self.writeUnicodeAtPos(
                    allocator,
                    size,
                    pos,
                    borderStyles.corners.bottomRight,
                    bottomRightCornerStyle,
                );
            }

            if (layoutInfo.height > 0) {
                pos.x = renderPos.x;
                pos.y = renderPos.y + layoutInfo.height - 1;
                const bottomLeftCornerStyle = if (cellFn) |func|
                    func(0, layoutInfo.height - 1, layoutInfo.width + adjustWidth, layoutInfo.height + adjustHeight) orelse
                        simpleStyles
                else
                    simpleStyles;
                try self.writeUnicodeAtPos(
                    allocator,
                    size,
                    pos,
                    borderStyles.corners.bottomLeft,
                    bottomLeftCornerStyle,
                );
            }

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
                const line = self.buffer.items[renderPos.y];
                if (layoutInfo.width == 0 or renderPos.x + 1 >= line.items.len) break :a;
                const from = renderPos.x + 1;
                const to = @min(
                    renderPos.x + layoutInfo.width - 1,
                    line.items.len,
                );
                if (from <= to) b: {
                    const cells = line.items[from..to];
                    @memset(cells, horizontalBorder);

                    const func = cellFn orelse break :b;
                    for (cells, 0..) |*cell, index| {
                        const cellStyleOrNull = func(
                            @intCast(index),
                            0,
                            layoutInfo.width + adjustWidth,
                            layoutInfo.height + adjustHeight,
                        );
                        const cellStyle = cellStyleOrNull orelse continue;
                        cell.style = cellStyle;
                    }
                }
            }

            a: {
                const line = self.buffer.items[renderPos.y + layoutInfo.height - 1];
                if (layoutInfo.width == 0 or renderPos.x + 1 >= line.items.len) break :a;
                const from = renderPos.x + 1;
                const to = @min(
                    renderPos.x + layoutInfo.width - 1,
                    line.items.len,
                );
                if (from <= to) b: {
                    const cells = line.items[from..to];
                    @memset(cells, horizontalBorder);

                    const func = cellFn orelse break :b;
                    for (cells, 0..) |*cell, index| {
                        const cellStyleOrNull = func(
                            @intCast(index),
                            layoutInfo.height - 1,
                            layoutInfo.width + adjustWidth,
                            layoutInfo.height + adjustHeight,
                        );
                        const cellStyle = cellStyleOrNull orelse continue;
                        cell.style = cellStyle;
                    }
                }
            }

            const endY = renderPos.y + layoutInfo.height - 1;
            var currentY: usize = renderPos.y + 1;
            var index: u16 = 0;
            while (currentY < endY) : ({
                currentY += 1;
                index += 1;
            }) {
                const line = self.buffer.items[currentY];
                if (layoutInfo.width == 0 or renderPos.x >= line.items.len) break;
                const leftCell = &line.items[renderPos.x];
                const leftCellStyleOrNull = if (cellFn) |func|
                    func(
                        0,
                        index,
                        layoutInfo.width + adjustWidth,
                        layoutInfo.height + adjustHeight,
                    )
                else
                    null;
                leftCell.* = verticalBorder;
                if (leftCellStyleOrNull) |leftCellStyle| leftCell.style = leftCellStyle;

                if (renderPos.x + layoutInfo.width - 1 >= line.items.len) continue;
                const rightCell = &line.items[renderPos.x + layoutInfo.width - 1];
                const rightCellStyleOrNull = if (cellFn) |func|
                    func(
                        layoutInfo.width - 1,
                        index,
                        layoutInfo.width,
                        layoutInfo.height,
                    )
                else
                    null;
                rightCell.* = verticalBorder;
                if (rightCellStyleOrNull) |rightCellStyle| rightCell.style = rightCellStyle;
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
            self.lineLimit = @max(self.lineLimit, lineIndex);
            return;
        }

        while (self.buffer.items.len < lineIndex) {
            const line = try bufferUtil.createLine(allocator, width);
            try self.buffer.append(allocator, line);
        }
        self.lineLimit = lineIndex;
    }
};
