pub const ScreenType = enum {
    Main,
    Alternate,
};

pub const Config = struct {
    screenType: ScreenType = .Main,
    rightPadding: ?u16 = null,
};
