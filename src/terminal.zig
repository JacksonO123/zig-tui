const std = @import("std");
const Allocator = std.mem.Allocator;

const ui = @import("ui.zig");

pub const Terminal = struct {
    const Self = @This();

    allocator: Allocator,

    pub inline fn init(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }
};
