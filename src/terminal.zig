const std = @import("std");
const Allocator = std.mem.Allocator;

const ui = @import("ui.zig");

pub const Terminal = struct {
    const Self = @This();

    allocator: Allocator,
    elements: std.ArrayList(ui.UIElement),

    pub inline fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .elements = .empty,
        };
    }

    pub fn appendElement(self: *Self, element: ui.UIElement) !void {
        try self.elements.append(self.allocator, element);
    }
};
