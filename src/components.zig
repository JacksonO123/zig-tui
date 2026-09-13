const std = @import("std");
const Allocator = std.mem.Allocator;

const constants = @import("constants.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");

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

    pub fn clone(self: Self, allocator: Allocator) !*ui.UIElement {
        const dataClone = try allocator.dupe(u8, self.data);
        var renderedDataClone = try allocator.alloc([]u8, self.renderedData.len);

        for (self.renderedData, 0..) |dataLine, index| {
            const dataLineClone = try allocator.dupe(u8, dataLine);
            renderedDataClone[index] = dataLineClone;
        }

        var textUiEl = try fromConstText(allocator, dataClone);
        textUiEl.variant.Text.renderedData = renderedDataClone;
        return textUiEl;
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
        gap: u32 = 0,

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

        pub fn gap(self: *BuilderSelf, amount: u32) *BuilderSelf {
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

    pub fn clone(self: Self, allocator: Allocator) !*ui.UIElement {
        const clonedElements = try allocator.dupe(?*ui.UIElement, self.data.elements);
        const clonedConstraints = try allocator.dupe(ui.Constraint, self.data.constraints);

        const clonedData = LayoutData{
            .elements = clonedElements,
            .constraints = clonedConstraints,
            .direction = self.data.direction,
            .alignment = self.data.alignment,
            .spacing = self.data.spacing,
            .gap = self.data.gap,
        };

        const layoutEl = ui.UIElement.fromVariant(.{ .Layout = .{ .data = clonedData } });
        return try layoutEl.alloc(allocator);
    }
};

pub const Input = struct {
    const InputData = struct {
        id: []const u8 = &.{},
        placeholder: ?[]const u8 = null,
        value: []const u8 = &.{},
        focused: bool = false,
    };

    const InputBuildError = error{
        InputIdCannotBeEmpty,
    };

    const InputBuilder = struct {
        const BuilderSelf = @This();

        allocator: Allocator,
        data: InputData,

        pub fn build(self: BuilderSelf) !*ui.UIElement {
            if (self.data.id.len == 0) return InputBuildError.InputIdCannotBeEmpty;
            return try internalInit(
                self.allocator,
                self.data.id,
                self.data.value,
                self.data.placeholder,
                self.data.focused,
            );
        }

        pub fn id(self: *BuilderSelf, inputId: []const u8) *BuilderSelf {
            self.data.id = inputId;
            return self;
        }

        pub fn placeholder(self: *BuilderSelf, inputPlaceholder: []const u8) *BuilderSelf {
            self.data.placeholder = inputPlaceholder;
            return self;
        }

        pub fn value(self: *BuilderSelf, inputValue: []const u8) *BuilderSelf {
            self.data.value = inputValue;
            return self;
        }

        pub fn focused(self: *BuilderSelf, inputFocused: bool) *BuilderSelf {
            self.data.focused = inputFocused;
            return self;
        }
    };

    fn internalInit(
        allocator: Allocator,
        id: []const u8,
        value: []const u8,
        placeholder: ?[]const u8,
        focused: bool,
    ) !*ui.UIElement {
        const renderStr = if (placeholder) |str| if (value.len == 0) str else value else value;

        const str = if (focused)
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ renderStr, "⎸" })
        else
            value;

        var text = try Text.fromConstText(allocator, str);
        if (placeholder != null and value.len == 0) {
            _ = text.styles.fg(constants.colors.gray);
        }

        const innerLayout = try Layout.builder(allocator, .Horizontal)
            .elements(&.{text})
            .constraints(&.{.{
                .width = .{ .Min = 24 },
            }})
            .build();

        const layout = try Layout.builder(allocator, .Horizontal)
            .elements(&.{innerLayout})
            .constraints(&.{.{
                .width = .{ .Max = 64 },
            }})
            .build();
        layout.id = id;

        return layout;
    }

    pub inline fn builder(allocator: Allocator) *InputBuilder {
        return @constCast(&InputBuilder{
            .allocator = allocator,
            .data = .{},
        });
    }
};

pub const Button = struct {
    pub fn create(allocator: Allocator, id: []const u8, label: []const u8) !*ui.UIElement {
        var text = try Text.fromConstText(allocator, label);
        text.id = id;
        return text;
    }
};
