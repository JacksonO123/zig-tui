const std = @import("std");
const Allocator = std.mem.Allocator;

const ui = @import("ui.zig");
const constants = @import("constants.zig");

pub const Text = struct {
    const Self = @This();

    data: []const u8,
    /// do not rely on this ptr
    renderedData: [][]u8,

    pub fn fromConstText(allocator: Allocator, str: []const u8) !*ui.UIElement {
        const el = ui.UIElement.fromVariant(.{
            .Text = .{
                .data = str,
                .renderedData = &.{},
            },
        });
        return el.alloc(allocator);
    }
};

const LayoutTypes = enum {
    Vertical,
    Horizontal,
};

const LayoutUtil = struct {
    const Self = @This();

    elements: []const ?*ui.UIElement,
    constraints: []ui.Constraint,

    pub fn getConstraint(self: Self, index: usize) ?ui.Constraint {
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
        elements: []const ?*ui.UIElement,
        direction: LayoutTypes,
    ) !*ui.UIElement {
        return fromElementsAndConstraints(allocator, elements, &.{}, direction);
    }

    pub fn fromElementsAndConstraints(
        allocator: Allocator,
        elements: []const ?*ui.UIElement,
        constraints: []const ui.Constraint,
        direction: LayoutTypes,
    ) !*ui.UIElement {
        const elementSlice = try allocator.dupe(?*ui.UIElement, elements);
        const constraintSlice = try allocator.dupe(ui.Constraint, constraints);

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
        const el = ui.UIElement.fromVariant(.{ .Layout = layout });
        return el.alloc(allocator);
    }

    pub fn getConstraint(self: Self, index: usize) ?ui.Constraint {
        return switch (self) {
            .Horizontal => |layout| layout.getConstraint(index),
            .Vertical => |layout| layout.getConstraint(index),
        };
    }
};

pub const Input = struct {
    fn internalInit(
        allocator: Allocator,
        id: []const u8,
        value: []const u8,
        isPlaceholder: bool,
        focused: bool,
    ) !*ui.UIElement {
        const str = if (!isPlaceholder and focused)
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ value, "⎸" })
        else
            value;

        var text = try Text.fromConstText(allocator, str);
        text.id = "inner";
        if (isPlaceholder) {
            _ = text.styles.fg(constants.colors.gray);
        }

        const innerLayout = try Layout.fromElementsAndConstraints(
            allocator,
            &.{text},
            &.{.{
                .width = .{ .Min = 24 },
            }},
            .Horizontal,
        );

        const layout = try Layout.fromElementsAndConstraints(
            allocator,
            &.{innerLayout},
            &.{.{ .width = .{ .Max = 64 } }},
            .Horizontal,
        );
        layout.id = id;

        return layout;
    }

    pub fn fromValue(
        allocator: Allocator,
        id: []const u8,
        value: []const u8,
        focused: bool,
    ) !*ui.UIElement {
        return internalInit(allocator, id, value, false, focused);
    }

    pub fn fromValueAndPlaceholder(
        allocator: Allocator,
        id: []const u8,
        value: []const u8,
        placeholder: []const u8,
        focused: bool,
    ) !*ui.UIElement {
        return internalInit(
            allocator,
            id,
            if (value.len == 0) placeholder else value,
            value.len == 0,
            focused,
        );
    }
};

pub const Button = struct {
    pub fn create(allocator: Allocator, id: []const u8, label: []const u8) !*ui.UIElement {
        var text = try Text.fromConstText(allocator, label);
        text.id = id;
        return text;
    }
};
