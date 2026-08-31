const utils = @import("../utils.zig");
const types = @import("../types.zig");

pub const StdinEvent = struct { []const u8 };

pub const ScrollDirection = enum {
    Up,
    Down,
};

pub const ScrollEvent = struct {
    direction: ScrollDirection,
    pos: utils.Pos,
};

pub const ScrollEventWrapper = struct { ScrollEvent };

pub const MouseEvent = struct {
    button: u8,
    x: u16,
    y: u16,
    pressed: bool,
};

pub const MouseEventButton = union(enum) {
    Other: u8,
    Left,
    Right,
};

pub const MouseButtonEvent = struct {
    const Self = @This();

    button: MouseEventButton,
    x: u16,
    y: u16,
    pressed: bool,

    pub fn toPos(self: Self) utils.Pos {
        return .{
            .x = self.x,
            .y = self.y,
        };
    }
};

pub const MouseButtonEventWrapper = struct { MouseButtonEvent };
