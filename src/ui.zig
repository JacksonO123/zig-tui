const std = @import("std");
const Allocator = std.mem.Allocator;

const components = @import("components.zig");
const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const stylesMod = @import("styles.zig");
const terminalUtils = @import("terminal_utils.zig");
const utils = @import("utils.zig");
const errors = @import("errors.zig");

pub const ElementLayoutInfo = struct {
    const Self = @This();

    width: u16 = 0,
    height: u16 = 1,
    xOffset: u16 = 0,
    yOffset: u16 = 0,

    pub fn offsetToPos(self: Self) utils.Pos {
        return .{
            .x = self.xOffset,
            .y = self.yOffset,
        };
    }
};

pub const UIElementVariant = union(enum) {
    Text: components.Text,
    Layout: components.Layout,
};

pub const UIElement = struct {
    const Self = @This();

    layoutInfo: ElementLayoutInfo = .{},
    styles: stylesMod.Styles = .default,
    variant: UIElementVariant,
    id: ?[]const u8 = null,

    pub fn fromVariant(variant: UIElementVariant) Self {
        return .{ .variant = variant };
    }

    pub fn alloc(self: Self, allocator: Allocator) !*Self {
        const ptr = try allocator.create(Self);
        ptr.* = self;
        return ptr;
    }
};

const ConstraintTypes = enum {
    Ratio,
    Percent,
    Value,
    Min,
    Max,
    None,
    Fill,
};

const ConstraintValues = union(ConstraintTypes) {
    Ratio: struct {
        numerator: u16,
        denominator: u16,
    },
    Percent: f64,
    Value: u16,
    Min: u16,
    Max: u16,
    None,
    Fill,
};

pub const Constraint = struct {
    width: ConstraintValues = .None,
    height: ConstraintValues = .None,
};

const TextRenderUtil = struct {
    const Self = @This();

    preAdjust: utils.Size,
    postAdjust: utils.Size,
    sizeConstraint: utils.Size,
    height: u16 = 1,
    width: u16 = 0,
    currentX: u16 = 0,
    lines: std.ArrayList([]u8) = .empty,
    line: std.ArrayList(u8) = .empty,
    styles: *stylesMod.Styles,

    pub fn init(
        preAdjust: utils.Size,
        postAdjust: utils.Size,
        sizeConstraint: utils.Size,
        styles: *stylesMod.Styles,
    ) Self {
        return .{
            .preAdjust = preAdjust,
            .postAdjust = postAdjust,
            .sizeConstraint = sizeConstraint,
            .styles = styles,
        };
    }

    pub fn render(
        self: *Self,
        allocator: Allocator,
        text: []const u8,
    ) (errors.InvalidUtf8 || Allocator.Error)!void {
        const utf8View = try std.unicode.Utf8View.init(text);
        var charIt = utf8View.iterator();

        if (self.preAdjust.height + self.postAdjust.height < self.sizeConstraint.height) {
            while (charIt.nextCodepointSlice()) |chars| {
                _ = try self.renderForSlice(allocator, chars, &charIt);
            }
        }

        if (self.line.items.len > 0) {
            try self.lines.append(allocator, self.line.items);
        }
    }

    /// returns should break
    fn tryNewline(self: *Self, allocator: Allocator) !bool {
        const currentElHeight = self.calculateCurrentHeight();
        if (currentElHeight >= self.sizeConstraint.height) {
            return true;
        }

        try self.lines.append(allocator, self.line.items);
        self.line = .empty;
        self.height += 1;
        self.currentX = 0;

        return false;
    }

    fn atOrAboveWidthLimit(self: Self) bool {
        return self.currentX + self.preAdjust.width + self.postAdjust.width >= self.sizeConstraint.width;
    }

    fn calculateCurrentHeight(self: Self) u16 {
        return self.height + self.preAdjust.height + self.postAdjust.height;
    }

    /// returns should break
    fn renderForSlice(
        self: *Self,
        allocator: Allocator,
        chars: []const u8,
        charIt: *std.unicode.Utf8Iterator,
    ) !bool {
        if (std.mem.eql(u8, chars, "\n")) {
            const shouldBreak = try self.tryNewline(allocator);
            if (shouldBreak) return true else return false;
        }

        if (self.atOrAboveWidthLimit()) {
            if (self.styles.styles.wordWrap) {
                var shouldBreak = try self.tryNewline(allocator);
                if (shouldBreak) return true;
                shouldBreak = try self.renderForSlice(allocator, chars, charIt);
                if (shouldBreak) return true;

                return false;
            }

            while (charIt.nextCodepointSlice()) |slice| {
                if (std.mem.eql(u8, slice, "\n")) break;
            }

            if (charIt.peek(1).len == 0) return true;

            const shouldBreak = try self.tryNewline(allocator);
            if (shouldBreak) return true;

            return false;
        }

        try self.line.appendSlice(allocator, chars);
        self.currentX += 1;
        self.width = @max(self.width, self.currentX);

        return false;
    }
};

pub fn setElementDimensions(
    allocator: Allocator,
    element: *UIElement,
    sizeConstraint: utils.Size,
    constraint: Constraint,
    writePosOffsetParam: utils.Pos,
    lastRelativeAnchor: ElementLayoutInfo,
) errors.SetElementDimensionsError!void {
    const writePosOffset: utils.Pos = switch (element.styles.styles.position) {
        .Relative => writePosOffsetParam,
        .Absolute => |translate| .{
            .x = lastRelativeAnchor.xOffset + translate.x,
            .y = lastRelativeAnchor.yOffset + translate.y,
        },
    };

    var elInfo: ElementLayoutInfo = .{
        .xOffset = writePosOffset.x,
        .yOffset = writePosOffset.y,
    };

    const preAdjust = getPreAdjustment(element.styles);
    const postAdjust = getPostAdjustment(element.styles);

    switch (element.variant) {
        .Text => |*text| {
            var textRenderer = TextRenderUtil.init(
                preAdjust,
                postAdjust,
                sizeConstraint,
                &element.styles,
            );
            try textRenderer.render(allocator, text.data);

            text.renderedData = textRenderer.lines.items;
            elInfo.width = textRenderer.width + preAdjust.width + postAdjust.width;
            elInfo.height = textRenderer.height + preAdjust.height + postAdjust.height;

            adjustElInfoDimensions(&elInfo, constraint, sizeConstraint);
        },
        .Layout => |layout| {
            elInfo.width += preAdjust.width + postAdjust.width;
            elInfo.height += preAdjust.height + postAdjust.height;

            switch (layout.data.direction) {
                .Horizontal => try setLayoutDimensions(
                    allocator,
                    .Horizontal,
                    element,
                    &elInfo,
                    layout,
                    constraint,
                    sizeConstraint,
                    preAdjust,
                    postAdjust,
                    lastRelativeAnchor,
                ),
                .Vertical => try setLayoutDimensions(
                    allocator,
                    .Vertical,
                    element,
                    &elInfo,
                    layout,
                    constraint,
                    sizeConstraint,
                    preAdjust,
                    postAdjust,
                    lastRelativeAnchor,
                ),
            }

            adjustElInfoDimensions(&elInfo, constraint, sizeConstraint);
        },
    }

    element.layoutInfo = elInfo;
}

fn applySizeConstraint(cons: ConstraintValues, dimensionConstraint: u16, fillSize: ?u16) u16 {
    return switch (cons) {
        .Min => |value| @max(value, dimensionConstraint),
        .Max => |value| @min(value, dimensionConstraint),
        .Ratio => |value| {
            const percent = @as(f32, @floatFromInt(value.numerator)) /
                @as(f32, @floatFromInt(value.denominator));
            const width = @round(dimensionConstraint * percent);
            return @intFromFloat(width);
        },
        .Percent => |value| {
            const width = @round(dimensionConstraint * value);
            return @intFromFloat(width);
        },
        .Value => |value| value,
        .Fill => if (fillSize) |size| size else dimensionConstraint,
        .None => dimensionConstraint,
    };
}

fn getSizeConstraint(
    currentSize: utils.Size,
    constraint: Constraint,
    fillWidthPerEl: ?u16,
    fillHeightPerEl: ?u16,
) utils.Size {
    var sizeCpy = currentSize;

    sizeCpy.width = applySizeConstraint(constraint.width, sizeCpy.width, fillWidthPerEl);
    sizeCpy.height = applySizeConstraint(constraint.height, sizeCpy.height, fillHeightPerEl);

    return sizeCpy;
}

pub fn getPreAdjustment(styles: stylesMod.Styles) utils.Size {
    var adjustment: utils.Size = .{};

    if (styles.hasBorder()) {
        adjustment.width += 1;
        adjustment.height += 1;
    }

    adjustment.width += styles.styles.padding.paddingLeft;
    adjustment.height += styles.styles.padding.paddingTop;

    return adjustment;
}

pub fn getPostAdjustment(styles: stylesMod.Styles) utils.Size {
    var adjustment: utils.Size = .{};

    if (styles.hasBorder()) {
        adjustment.width += 1;
        adjustment.height += 1;
    }

    adjustment.width += styles.styles.padding.paddingRight;
    adjustment.height += styles.styles.padding.paddingBottom;

    return adjustment;
}

fn trimTextElContentToWidth(el: *UIElement, width: u16) void {
    if (el.variant != .Text) return;

    for (el.variant.Text.renderedData) |*line| {
        line.len = @min(line.len, width);
    }
}

pub fn getIdsContainingPoint(
    allocator: Allocator,
    element: *UIElement,
    point: utils.Pos,
    ids: *std.ArrayList([]const u8),
) !void {
    return getIdsContainingPointImpl(allocator, element, point, ids, .{});
}

pub fn getIdsContainingPointImpl(
    allocator: Allocator,
    element: *UIElement,
    point: utils.Pos,
    ids: *std.ArrayList([]const u8),
    posAcc: utils.Pos,
) !void {
    const newPosAcc = posAcc.appendOffset(element.layoutInfo.offsetToPos());

    switch (element.variant) {
        .Text => a: {
            if (!pointInElement(element.layoutInfo, newPosAcc, point)) break :a;
            const id = element.id orelse break :a;
            try ids.append(allocator, id);
        },
        .Layout => |layout| a: {
            if (!pointInElement(element.layoutInfo, newPosAcc, point)) break :a;

            if (element.id) |id| {
                try ids.append(allocator, id);
            }

            const elements = switch (layout) {
                .Horizontal => |info| info.data.elements,
                .Vertical => |info| info.data.elements,
            };

            for (elements) |elOrNull| {
                const el = elOrNull orelse continue;
                try getIdsContainingPointImpl(allocator, el, point, ids, newPosAcc);
            }
        },
    }
}

fn pointInElement(layoutInfo: ElementLayoutInfo, posAcc: utils.Pos, point: utils.Pos) bool {
    const inX = point.x > posAcc.x and point.x <= posAcc.x + layoutInfo.width;
    const inY = point.y > posAcc.y and point.y <= posAcc.y + layoutInfo.height;
    return inX and inY;
}

fn countRelativeElements(elements: []const ?*UIElement) usize {
    var res: usize = 0;

    for (elements) |elOrNull| {
        const el = elOrNull orelse continue;
        if (el.styles.styles.position == .Relative) {
            res += 1;
        }
    }

    return res;
}

fn adjustElInfoDimensions(
    elInfo: *ElementLayoutInfo,
    constraint: Constraint,
    sizeConstraint: utils.Size,
) void {
    const maxWidthWithConstraintValue = switch (constraint.width) {
        .Value, .Percent, .Ratio => true,
        .Max, .Min, .None, .Fill => false,
    };
    const maxHeightWithConstraintValue = switch (constraint.height) {
        .Value, .Percent, .Ratio => true,
        .Max, .Min, .None, .Fill => false,
    };

    const finalElWidth = elInfo.width;
    elInfo.width = if (maxWidthWithConstraintValue)
        @max(finalElWidth, sizeConstraint.width)
    else
        finalElWidth;

    if (constraint.width == .Min) {
        elInfo.width = @max(elInfo.width, constraint.width.Min);
    }

    const finalElHeight = elInfo.height;
    elInfo.height = if (maxHeightWithConstraintValue)
        @max(finalElHeight, sizeConstraint.height)
    else
        finalElHeight;

    if (constraint.height == .Min) {
        elInfo.height = @max(elInfo.height, constraint.height.Min);
    }
}

fn setLayoutDimensions(
    allocator: Allocator,
    comptime layoutType: components.LayoutTypes,
    element: *UIElement,
    elInfo: *ElementLayoutInfo,
    layout: components.Layout,
    constraint: Constraint,
    sizeConstraint: utils.Size,
    preAdjust: utils.Size,
    postAdjust: utils.Size,
    lastRelativeAnchor: ElementLayoutInfo,
) errors.SetElementDimensionsError!void {
    var fillSizeIndices: std.ArrayList(usize) = .empty;
    defer fillSizeIndices.deinit(allocator);

    var absoluteElIndices: std.ArrayList(usize) = .empty;
    defer absoluteElIndices.deinit(allocator);

    const numRelative = countRelativeElements(layout.data.elements);
    var possibleFillSize = if (layoutType == .Horizontal)
        sizeConstraint.width - (preAdjust.width + postAdjust.width)
    else
        sizeConstraint.height - (preAdjust.height + postAdjust.height);

    if (layoutType == .Vertical) {
        elInfo.height = 0;
    }

    for (layout.data.elements, 0..) |elOrNull, index| {
        const el = elOrNull orelse continue;

        if (el.styles.styles.position == .Absolute) {
            try absoluteElIndices.append(allocator, index);
            continue;
        }

        const layoutConstraint = layout.data.getConstraint(index);
        const newSizeConstraint, const newElConstraint = if (layoutConstraint) |cons| a: {
            var newConstraint = getSizeConstraint(
                sizeConstraint,
                cons,
                null,
                null,
            );
            newConstraint.width -|= preAdjust.width + postAdjust.width;
            newConstraint.height -|= preAdjust.height + postAdjust.height;

            break :a .{
                newConstraint,
                cons,
            };
        } else .{ sizeConstraint, Constraint{} };

        const innerElPos = utils.Pos{
            .x = preAdjust.width,
            .y = preAdjust.height,
        };
        try setElementDimensions(
            allocator,
            el,
            newSizeConstraint,
            newElConstraint,
            innerElPos,
            lastRelativeAnchor,
        );
        switch (layoutType) {
            .Horizontal => {
                elInfo.width += el.layoutInfo.width;
                elInfo.height = @max(
                    elInfo.height,
                    el.layoutInfo.height + preAdjust.height + postAdjust.height,
                );
            },
            .Vertical => {
                elInfo.height += el.layoutInfo.height;
                elInfo.width = @max(
                    elInfo.width,
                    el.layoutInfo.width + preAdjust.width + postAdjust.width,
                );
            },
        }

        if (index + 1 < numRelative) {
            switch (layoutType) {
                .Horizontal => {
                    elInfo.width += layout.data.gap;
                },
                .Vertical => {
                    elInfo.height += layout.data.gap;
                },
            }

            possibleFillSize -|= layout.data.gap;
        }

        if (layoutConstraint != null and
            (if (layoutType == .Horizontal)
                layoutConstraint.?.width
            else
                layoutConstraint.?.height) == .Fill)
        {
            try fillSizeIndices.append(allocator, index);
        } else {
            possibleFillSize -|= if (layoutType == .Horizontal)
                el.layoutInfo.width
            else
                el.layoutInfo.height;
        }
    }

    const newRelativeAnchor: ElementLayoutInfo = if (element.styles.styles.relativeAnchor)
        elInfo.*
    else
        lastRelativeAnchor;

    const absoluteSizeConstraint = utils.Size{
        .width = newRelativeAnchor.width,
        .height = newRelativeAnchor.height,
    };

    for (absoluteElIndices.items) |index| {
        const elOrNull = layout.data.elements[index];
        const el = elOrNull orelse continue;
        try setElementDimensions(
            allocator,
            el,
            absoluteSizeConstraint,
            constraint,
            .{},
            newRelativeAnchor,
        );
    }

    var elSizes = try allocator.alloc(u16, fillSizeIndices.items.len);
    defer allocator.free(elSizes);

    var fillItemCount = fillSizeIndices.items.len;
    var remainingSizeBudget = possibleFillSize;
    var i: usize = 0;
    while (fillItemCount > 0) : ({
        i += 1;
        fillItemCount -= 1;
    }) {
        const amount = remainingSizeBudget / @as(u16, @intCast(fillItemCount));
        elSizes[i] = amount;
        remainingSizeBudget -= amount;
    }

    const numElsMinusOne: u16 = @intCast(layout.data.elements.len -| 1);
    var gapAmount, const availableFillSize = switch (layout.data.spacing) {
        .Normal => .{ 0, possibleFillSize },
        .Between => .{
            (possibleFillSize / @as(u16, @max(1, numElsMinusOne))) + (layout.data.gap * numElsMinusOne),
            0,
        },
        .Evenly => .{
            (possibleFillSize / @as(
                u16,
                @intCast(layout.data.elements.len + 1),
            )) + (layout.data.gap * numElsMinusOne),
            0,
        },
    };
    gapAmount = @max(layout.data.gap, gapAmount);
    var sizeAcc: u16 = switch (layout.data.alignment) {
        .Start => 0,
        .Center => availableFillSize / 2,
        .End => availableFillSize,
    };

    if (layout.data.spacing == .Evenly) {
        sizeAcc += gapAmount -| layout.data.gap;
    }

    i = 0;
    for (layout.data.elements, 0..) |elOrNull, index| {
        const el = elOrNull orelse continue;
        if (el.styles.styles.position == .Absolute) continue;

        const layoutConstraint = layout.data.getConstraint(index);
        if (layoutConstraint) |cons| {
            const elPreAdjust = getPreAdjustment(el.styles);
            const elPostAdjust = getPostAdjustment(el.styles);

            const constraintTarget = if (layoutType == .Horizontal) cons.width else cons.height;
            const inverseConstraintTarget = if (layoutType == .Horizontal) cons.height else cons.width;

            if (constraintTarget == .Fill) {
                switch (layoutType) {
                    .Horizontal => {
                        el.layoutInfo.width = @max(
                            elSizes[i],
                            elPreAdjust.width + elPostAdjust.width,
                        );
                        trimTextElContentToWidth(
                            el,
                            elSizes[i] -| (elPreAdjust.width + elPostAdjust.width),
                        );

                        i += 1;
                    },
                    .Vertical => {
                        el.layoutInfo.height = @max(
                            elSizes[i],
                            elPreAdjust.height + elPostAdjust.height,
                        );
                        i += 1;
                    },
                }
            }

            if (inverseConstraintTarget == .Fill) {
                switch (layoutType) {
                    .Horizontal => {
                        el.layoutInfo.height = @max(
                            el.layoutInfo.height,
                            elPreAdjust.height + elPostAdjust.height,
                            sizeConstraint.height,
                        );
                    },
                    .Vertical => {
                        el.layoutInfo.width = @max(
                            el.layoutInfo.width,
                            elPreAdjust.width + elPostAdjust.width,
                            sizeConstraint.width,
                        );
                    },
                }
            }
        }

        switch (layoutType) {
            .Horizontal => {
                el.layoutInfo.xOffset = elInfo.xOffset + preAdjust.width + sizeAcc;
            },
            .Vertical => {
                el.layoutInfo.yOffset = elInfo.yOffset + preAdjust.height + sizeAcc;
            },
        }

        switch (layoutType) {
            .Horizontal => sizeAcc += el.layoutInfo.width,
            .Vertical => sizeAcc += el.layoutInfo.height,
        }

        if (index + 1 < numRelative) {
            sizeAcc += gapAmount;
        }
    }
}
