const std = @import("std");
const Allocator = std.mem.Allocator;

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

    pub fn fromConstText(allocator: Allocator, str: []const u8) !*UIElement {
        const el = UIElement.fromVariant(.{
            .Text = .{
                .data = str,
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

pub fn setElementDimensions(
    element: *UIElement,
    sizeConstraint: utils.Size,
    writePos: utils.Pos,
) void {
    var elInfo: ElementLayoutInfo = .{
        .x = writePos.x,
        .y = writePos.y,
    };

    const preAdjust = getPreAdjustment(element.styles);
    const postAdjust = getPostAdjustment(element.styles);

    switch (element.variant) {
        .Text => |text| {
            var currentX: u16 = 0;
            for (text.data) |char| {
                if (char == '\n') {
                    const currentElHeight = elInfo.height + preAdjust.height + postAdjust.height;
                    if (currentElHeight >= sizeConstraint.height) {
                        break;
                    }

                    elInfo.height += 1;
                    currentX = 0;
                    continue;
                }

                if (currentX + preAdjust.width + postAdjust.width >= sizeConstraint.width) {
                    break;
                }

                currentX += 1;
                elInfo.width = @max(elInfo.width, currentX);
            }

            elInfo.width += preAdjust.width + postAdjust.width;
            elInfo.height += preAdjust.height + postAdjust.height;
        },
        .Layout => |layout| {
            elInfo.width += preAdjust.width + postAdjust.width;
            elInfo.height += preAdjust.height + postAdjust.height;

            switch (layout) {
                .Horizontal => |layoutInfo| {
                    for (layoutInfo.elements, 0..) |el, index| {
                        const constraint = layoutInfo.getConstraint(index);
                        const newSizeConstraint = if (constraint) |cons|
                            getSizeConstraint(sizeConstraint, cons)
                        else
                            sizeConstraint;

                        const innerElPos = utils.Pos{
                            .x = elInfo.x + preAdjust.width + elInfo.width,
                            .y = elInfo.y + preAdjust.height,
                        };
                        setElementDimensions(el, newSizeConstraint, innerElPos);
                        correctElSizeToPossibleConstraint(el, constraint);
                        elInfo.width += el.layoutInfo.width;
                        elInfo.height = @max(elInfo.height, el.layoutInfo.height);
                    }
                },
                .Vertical => |layoutInfo| {
                    if (layoutInfo.elements.len > 0) {
                        elInfo.height = 0;
                    }

                    for (layoutInfo.elements) |el| {
                        const innerElPos = utils.Pos{
                            .x = elInfo.x + preAdjust.width,
                            .y = elInfo.y + preAdjust.height + elInfo.height,
                        };
                        setElementDimensions(el, sizeConstraint, innerElPos);
                        elInfo.height += el.layoutInfo.height;
                        elInfo.width = @max(elInfo.width, el.layoutInfo.width);
                    }
                },
            }
        },
    }

    element.layoutInfo = elInfo;
}

fn correctElSizeToPossibleConstraint(el: *UIElement, constraint: ?Constraint) void {
    if (constraint) |cons| {
        switch (cons.width) {
            .Min => |value| {
                el.layoutInfo.width = @max(value, el.layoutInfo.width);
            },
            else => {},
        }

        switch (cons.height) {
            .Min => |value| {
                el.layoutInfo.height = @max(value, el.layoutInfo.height);
            },
            else => {},
        }
    }
}

fn getSizeConstraint(currentSize: utils.Size, constraint: Constraint) utils.Size {
    var sizeCpy = currentSize;

    getSizeConstraintUtil(&sizeCpy, constraint, "width");
    getSizeConstraintUtil(&sizeCpy, constraint, "height");

    return sizeCpy;
}

fn getSizeConstraintUtil(
    sizeCpy: *utils.Size,
    constraint: anytype,
    comptime field: []const u8,
) void {
    if (!@hasField(@TypeOf(constraint), field)) {
        @compileError("Expected " ++ @typeName(@TypeOf(constraint)) ++ " to have field " ++ field);
    }

    if (!@hasField(@TypeOf(sizeCpy.*), field)) {
        @compileError("Expected " ++ @typeName(@TypeOf(sizeCpy.*)) ++ " to have field " ++ field);
    }

    switch (@field(constraint, field)) {
        .Min => |value| {
            @field(sizeCpy, field) = @max(@field(sizeCpy, field), value);
        },
        .Max => |value| {
            @field(sizeCpy, field) = @min(@field(sizeCpy, field), value);
        },
        else => {},
    }
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
