const types = @import("types.zig");

pub const ScreenType = enum {
    Main,
    Alternate,
};

pub const Config = struct {
    screenType: ScreenType = .Alternate,
    rightPadding: ?u32 = null,
};
