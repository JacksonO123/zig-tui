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

pub const LayoutTypes = enum {
    Vertical,
    Horizontal,
};

pub const AlignmentDirections = enum {
    Start,
    Center,
    End,
};

pub const LayoutSpacing = enum {
    Normal,
    Between,
    Evenly,
};

pub const Layout = struct {
    const Self = @This();

    const LayoutData = struct {
        elements: []const ?*ui.UIElement = &.{},
        constraints: []const ui.Constraint = &.{},
        direction: LayoutTypes,
        alignment: AlignmentDirections = .Start,
        spacing: LayoutSpacing = .Normal,
        gap: u16 = 0,

        pub fn getConstraint(self: @This(), index: usize) ?ui.Constraint {
            if (index < self.constraints.len) {
                return self.constraints[index];
            }

            return null;
        }
    };

    const LayoutBuilder = struct {
        const BuilderSelf = @This();

        allocator: Allocator,
        data: LayoutData,
        err: ?Allocator.Error = null,

        pub fn build(self: BuilderSelf) !*ui.UIElement {
            if (self.err) |err| return err;
            const el = ui.UIElement.fromVariant(.{ .Layout = .{ .data = self.data } });
            return try el.alloc(self.allocator);
        }

        pub fn elements(self: *BuilderSelf, elementSlice: []const ?*ui.UIElement) *BuilderSelf {
            if (self.err != null) return self;
            const sliceClone = self.allocator.dupe(?*ui.UIElement, elementSlice) catch |err| {
                self.err = err;
                return self;
            };
            self.data.elements = sliceClone;
            return self;
        }

        pub fn constraints(self: *BuilderSelf, constraintSlice: []const ui.Constraint) *BuilderSelf {
            if (self.err != null) return self;
            self.data.constraints = self.allocator.dupe(ui.Constraint, constraintSlice) catch |err| {
                self.err = err;
                return self;
            };
            return self;
        }

        pub fn alignment(self: *BuilderSelf, alignmentDirection: AlignmentDirections) *BuilderSelf {
            self.data.alignment = alignmentDirection;
            return self;
        }

        pub fn spacing(self: *BuilderSelf, spacingType: LayoutSpacing) *BuilderSelf {
            self.data.spacing = spacingType;
            return self;
        }

        pub fn gap(self: *BuilderSelf, amount: u16) *BuilderSelf {
            self.data.gap = amount;
            return self;
        }
    };

    data: LayoutData,

    pub inline fn builder(allocator: Allocator, direction: LayoutTypes) *LayoutBuilder {
        return @constCast(&LayoutBuilder{
            .allocator = allocator,
            .data = .{
                .direction = direction,
            },
        });
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
