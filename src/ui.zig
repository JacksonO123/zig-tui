const std = @import("std");
const Allocator = std.mem.Allocator;

const styles = @import("styles.zig");

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

    styles: styles.Styles = .default,
    variant: UIElementVariant,

    pub fn fromVariant(variant: UIElementVariant) Self {
        return .{ .variant = variant };
    }
};

const LayoutTypes = enum {
    Vertical,
    Horizontal,
};

pub const Text = struct {
    const Self = @This();

    data: []const u8,

    pub fn fromConstText(str: []const u8) UIElement {
        return UIElement.fromVariant(.{
            .Text = .{
                .data = str,
            },
        });
    }
};

pub const Layout = union(LayoutTypes) {
    const Self = @This();

    Vertical: []UIElement,
    Horizontal: []UIElement,

    pub fn fromElements(allocator: Allocator, elements: []const UIElement, dir: LayoutTypes) !UIElement {
        const slice = try allocator.dupe(UIElement, elements);

        const layout: Self = switch (dir) {
            .Vertical => .{ .Vertical = slice },
            .Horizontal => .{ .Horizontal = slice },
        };
        return UIElement.fromVariant(.{ .Layout = layout });
    }
};
