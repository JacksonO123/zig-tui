const std = @import("std");
const Allocator = std.mem.Allocator;

const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;
const stylesMod = @import("styles.zig");
const utils = @import("utils.zig");

pub const ElementLayoutInfo = struct {
    width: u16 = 0,
    height: u16 = 1,
    x: u16 = 0,
    y: u16 = 0,
};

pub const UIElementTypes = enum {
    Text,
    Layout,
};

pub const UIElementVariant = union(UIElementTypes) {
    Text: Text,
    Layout: Layout,
};

pub const UIElement = struct {
    const Self = @This();

    layoutInfo: ElementLayoutInfo = .{},
    styles: stylesMod.Styles = .default,
    variant: UIElementVariant,

    pub fn fromVariant(variant: UIElementVariant) Self {
        return .{ .variant = variant };
    }

    pub fn alloc(self: Self, allocator: Allocator) !*Self {
        const ptr = try allocator.create(Self);
        ptr.* = self;
        return ptr;
    }
};

pub const Text = struct {
    const Self = @This();

    data: []const u8,
    /// do not rely on this ptr
    renderedData: [][]u8,

    pub fn fromConstText(allocator: Allocator, str: []const u8) !*UIElement {
        const el = UIElement.fromVariant(.{
            .Text = .{
                .data = str,
                .renderedData = &.{},
            },
        });
        return el.alloc(allocator);
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
    Percent: f32,
    Value: u16,
    Min: u16,
    Max: u16,
    None,
    Fill,
};

const Constraint = struct {
    width: ConstraintValues = .None,
    height: ConstraintValues = .None,
};

const LayoutTypes = enum {
    Vertical,
    Horizontal,
};

const LayoutUtil = struct {
    const Self = @This();

    elements: []const *UIElement,
    constraints: []Constraint,

    pub fn getConstraint(self: Self, index: usize) ?Constraint {
        if (index < self.constraints.len) {
            return self.constraints[index];
        }

        return null;
    }
};

pub const Layout = union(LayoutTypes) {
    const Self = @This();

    Vertical: LayoutUtil,
    Horizontal: LayoutUtil,

    pub fn fromElements(
        allocator: Allocator,
        elements: []const *UIElement,
        direction: LayoutTypes,
    ) !*UIElement {
        return fromElementsAndConstraints(allocator, elements, &.{}, direction);
    }

    pub fn fromElementsAndConstraints(
        allocator: Allocator,
        elements: []const *UIElement,
        constraints: []const Constraint,
        direction: LayoutTypes,
    ) !*UIElement {
        const elementSlice = try allocator.dupe(*UIElement, elements);
        const constraintSlice = try allocator.dupe(Constraint, constraints);

        const layout: Self = switch (direction) {
            .Vertical => .{
                .Vertical = .{
                    .elements = elementSlice,
                    .constraints = constraintSlice,
                },
            },
            .Horizontal => .{
                .Horizontal = .{
                    .elements = elementSlice,
                    .constraints = constraintSlice,
                },
            },
        };
        const el = UIElement.fromVariant(.{ .Layout = layout });
        return el.alloc(allocator);
    }

    pub fn getConstraint(self: Self, index: usize) ?Constraint {
        return switch (self) {
            .Horizontal => |layout| layout.getConstraint(index),
            .Vertical => |layout| layout.getConstraint(index),
        };
    }
};

var logged = false;

pub fn setElementDimensions(
    comptime ModelType: type,
    allocator: Allocator,
    context: *RenderContext(ModelType),
    element: *UIElement,
    sizeConstraint: utils.Size,
    constraint: Constraint,
    writePos: utils.Pos,
) !void {
    var elInfo: ElementLayoutInfo = .{
        .x = writePos.x,
        .y = writePos.y,
    };

    const preAdjust = getPreAdjustment(element.styles);
    const postAdjust = getPostAdjustment(element.styles);

    switch (element.variant) {
        .Text => |text| {
            var currentX: u16 = 0;
            var i: usize = 0;

            var lines: std.ArrayList([]u8) = .empty;
            var line: std.ArrayList(u8) = .empty;

            while (i < text.data.len) : (i += 1) {
                const char = text.data[i];

                if (char == '\n') {
                    const currentElHeight = elInfo.height + preAdjust.height + postAdjust.height;
                    if (currentElHeight >= sizeConstraint.height) {
                        break;
                    }

                    try lines.append(allocator, line.items);
                    line = .empty;
                    elInfo.height += 1;
                    currentX = 0;

                    continue;
                }

                if (currentX + preAdjust.width + postAdjust.width >= sizeConstraint.width) {
                    while (i < text.data.len and text.data[i] != '\n') : (i += 1) {}

                    if (i >= text.data.len or text.data[i] != '\n') break;

                    const currentElHeight = elInfo.height + preAdjust.height + postAdjust.height;
                    if (currentElHeight >= sizeConstraint.height) {
                        break;
                    }

                    try lines.append(allocator, line.items);
                    line = .empty;
                    elInfo.height += 1;
                    currentX = 0;

                    continue;
                }

                try line.append(allocator, char);
                currentX += 1;
                elInfo.width = @max(elInfo.width, currentX);
            }

            if (line.items.len > 0) {
                try lines.append(allocator, line.items);
            }

            element.variant.Text.renderedData = lines.items;

            const maxWidthWithConstraintValue = switch (constraint.width) {
                .Value, .Percent, .Ratio => true,
                .Max, .Min, .None, .Fill => false,
            };
            const maxHeightWithConstraintValue = switch (constraint.width) {
                .Value, .Percent, .Ratio => true,
                .Max, .Min, .None, .Fill => false,
            };

            const finalElWidth = elInfo.width + preAdjust.width + postAdjust.width;
            elInfo.width = if (maxWidthWithConstraintValue)
                @max(finalElWidth, sizeConstraint.width)
            else
                finalElWidth;

            const finalElHeight = elInfo.height + preAdjust.height + postAdjust.height;
            elInfo.height = if (maxHeightWithConstraintValue)
                @max(finalElHeight, sizeConstraint.height)
            else
                finalElHeight;
        },
        .Layout => |layout| {
            elInfo.width += preAdjust.width + postAdjust.width;
            elInfo.height += preAdjust.height + postAdjust.height;

            switch (layout) {
                .Horizontal => |layoutInfo| {
                    var fillWidthIndices: std.ArrayList(usize) = .empty;
                    defer fillWidthIndices.deinit(allocator);

                    var possibleFillWidth = sizeConstraint.width;

                    for (layoutInfo.elements, 0..) |el, index| {
                        const layoutConstraint = layoutInfo.getConstraint(index);
                        const newSizeConstraint, const newElConstraint = if (layoutConstraint) |cons|
                            .{
                                getSizeConstraint(
                                    sizeConstraint,
                                    cons,
                                    null,
                                    null,
                                ),
                                cons,
                            }
                        else
                            .{ sizeConstraint, constraint };

                        const innerElPos = utils.Pos{
                            .x = elInfo.x + preAdjust.width + elInfo.width,
                            .y = elInfo.y + preAdjust.height,
                        };
                        try setElementDimensions(
                            ModelType,
                            allocator,
                            context,
                            el,
                            newSizeConstraint,
                            newElConstraint,
                            innerElPos,
                        );
                        elInfo.width += el.layoutInfo.width;
                        elInfo.height = @max(elInfo.height, el.layoutInfo.height);

                        if (index + 1 < layoutInfo.elements.len) {
                            elInfo.width += element.styles.styles.gap;
                            possibleFillWidth -= element.styles.styles.gap;
                        }

                        if (layoutConstraint) |cons| {
                            if (cons.width == .Fill) {
                                try fillWidthIndices.append(allocator, index);
                            } else {
                                possibleFillWidth -= el.layoutInfo.width;
                            }
                        } else {
                            possibleFillWidth -|= el.layoutInfo.width;
                        }
                    }

                    var elWidths = try allocator.alloc(u16, fillWidthIndices.items.len);
                    defer allocator.free(elWidths);

                    var fillItemCount = fillWidthIndices.items.len;
                    var remainingWidthBudget = possibleFillWidth;
                    var i: usize = 0;
                    while (fillItemCount > 0) : ({
                        i += 1;
                        fillItemCount -= 1;
                    }) {
                        const amount = remainingWidthBudget / @as(u16, @intCast(fillItemCount));
                        elWidths[i] = amount;
                        remainingWidthBudget -= amount;
                    }

                    var widthAcc: u16 = 0;
                    i = 0;
                    for (layoutInfo.elements, 0..) |el, index| {
                        el.layoutInfo.x = elInfo.x + preAdjust.width + widthAcc;

                        const layoutConstraint = layoutInfo.getConstraint(index);
                        if (layoutConstraint) |cons| {
                            const elPreAdjust = getPreAdjustment(el.styles);
                            const elPostAdjust = getPostAdjustment(el.styles);

                            if (cons.width == .Fill) {
                                el.layoutInfo.width = @max(
                                    elWidths[i],
                                    elPreAdjust.width + elPostAdjust.width,
                                );
                                trimTextElContentToWidth(
                                    el,
                                    elWidths[i] -| (elPreAdjust.width + elPostAdjust.width),
                                );

                                i += 1;
                            }

                            if (cons.height == .Fill) {
                                el.layoutInfo.height = @max(
                                    el.layoutInfo.height,
                                    elPreAdjust.height + elPostAdjust.height,
                                    sizeConstraint.height,
                                );
                            }
                        }

                        widthAcc += el.layoutInfo.width;
                        if (index < layoutInfo.elements.len - 1) {
                            widthAcc += element.styles.styles.gap;
                        }
                    }
                },
                .Vertical => |layoutInfo| {
                    var fillHeightIndices: std.ArrayList(usize) = .empty;
                    defer fillHeightIndices.deinit(allocator);

                    var possibleFillHeight = sizeConstraint.height;

                    elInfo.height = 0;

                    for (layoutInfo.elements, 0..) |el, index| {
                        const layoutConstraint = layoutInfo.getConstraint(index);
                        const newSizeConstraint, const newElConstraint = if (layoutConstraint) |cons|
                            .{
                                getSizeConstraint(
                                    sizeConstraint,
                                    cons,
                                    null,
                                    null,
                                ),
                                cons,
                            }
                        else
                            .{ sizeConstraint, constraint };

                        const innerElPos = utils.Pos{
                            .x = elInfo.x + preAdjust.width,
                            .y = elInfo.y + preAdjust.height + elInfo.height,
                        };
                        try setElementDimensions(
                            ModelType,
                            allocator,
                            context,
                            el,
                            newSizeConstraint,
                            newElConstraint,
                            innerElPos,
                        );
                        elInfo.height += el.layoutInfo.height;
                        elInfo.width = @max(elInfo.width, el.layoutInfo.width);

                        if (index + 1 < layoutInfo.elements.len) {
                            elInfo.height += element.styles.styles.gap;
                            possibleFillHeight -= element.styles.styles.gap;
                        }

                        if (layoutConstraint) |cons| {
                            if (cons.height == .Fill) {
                                try fillHeightIndices.append(allocator, index);
                            } else {
                                possibleFillHeight -= el.layoutInfo.height;
                            }
                        } else {
                            possibleFillHeight -|= el.layoutInfo.height;
                        }
                    }

                    var elHeights = try allocator.alloc(u16, fillHeightIndices.items.len);
                    defer allocator.free(elHeights);

                    var fillItemCount = fillHeightIndices.items.len;
                    var remainingHeightBudget = possibleFillHeight;
                    var i: usize = 0;
                    while (fillItemCount > 0) : ({
                        i += 1;
                        fillItemCount -= 1;
                    }) {
                        const amount = remainingHeightBudget / @as(u16, @intCast(fillItemCount));
                        elHeights[i] = amount;
                        remainingHeightBudget -= amount;
                    }

                    var heightAcc: u16 = 0;
                    i = 0;
                    for (layoutInfo.elements, 0..) |el, index| {
                        el.layoutInfo.y = elInfo.y + preAdjust.height + heightAcc;

                        const layoutConstraint = layoutInfo.getConstraint(index);
                        if (layoutConstraint) |cons| {
                            const elPreAdjust = getPreAdjustment(el.styles);
                            const elPostAdjust = getPostAdjustment(el.styles);

                            if (cons.height == .Fill) {
                                el.layoutInfo.height = @max(
                                    elHeights[i],
                                    elPreAdjust.height + elPostAdjust.height,
                                );
                                i += 1;
                            }

                            if (cons.width == .Fill) {
                                el.layoutInfo.width = @max(
                                    el.layoutInfo.width,
                                    elPreAdjust.width + elPostAdjust.width,
                                    sizeConstraint.width,
                                );
                            }
                        }

                        heightAcc += el.layoutInfo.height;
                        if (index < layoutInfo.elements.len - 1) {
                            heightAcc += element.styles.styles.gap;
                        }
                    }
                },
            }
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
