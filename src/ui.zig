const std = @import("std");
const Allocator = std.mem.Allocator;

const stylesMod = @import("styles.zig");
const utils = @import("utils.zig");

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

    size: utils.Size = .{},
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
};

const Constraint = union(ConstraintTypes) {
    Ratio: struct {
        numerator: u16,
        denominator: u16,
    },
    Percent: f32,
    Value: u16,
    Min: u16,
    Max: u16,
};

const LayoutTypes = enum {
    Vertical,
    Horizontal,
};

const LayoutUtil = struct {
    elements: []const *UIElement,
    constraints: []Constraint,
};

pub const Layout = union(LayoutTypes) {
    const Self = @This();

    Vertical: []const *UIElement,
    Horizontal: []const *UIElement,

    pub fn fromElements(
        allocator: Allocator,
        elements: []const *UIElement,
        direction: LayoutTypes,
    ) !*UIElement {
        const slice = try allocator.dupe(*UIElement, elements);

        const layout: Self = switch (direction) {
            .Vertical => .{
                .Vertical = .{
                    .elements = slice,
                    .constraints = &.{},
                },
            },
            .Horizontal => .{
                .Horizontal = .{
                    .elements = slice,
                    .constraints = &.{},
                },
            },
        };
        const el = UIElement.fromVariant(.{ .Layout = layout });
        return el.alloc(allocator);
    }

    pub fn fromElementsAndConstraints(
        allocator: Allocator,
        elements: []const *UIElement,
        constraints: []Constraint,
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
};

pub fn setElementDimensions(element: *UIElement) void {
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
                        setElementDimensions(el);
                        size.width += el.size.width;
                        size.height = @max(size.height, el.size.height);
                    }
                },
                .Vertical => |elements| {
                    if (elements.len > 0) {
                        size.height = 0;
                    }

                    for (elements) |el| {
                        setElementDimensions(el);
                        size.height += el.size.height;
                        size.width = @max(size.width, el.size.width);
                    }
                },
            }
        },
    }

    element.size = size;
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
