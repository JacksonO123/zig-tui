const utils = @import("../utils.zig");

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

pub const MouseEventWrapper = struct { MouseEvent };
