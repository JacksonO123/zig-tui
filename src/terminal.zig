const std = @import("std");
const Allocator = std.mem.Allocator;

const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub const Terminal = struct {
    const Self = @This();

    allocator: Allocator,
    size: utils.WinSize,

    pub inline fn init(allocator: Allocator, size: utils.WinSize) Self {
        return .{
            .allocator = allocator,
            .size = size,
        };
    }
};
