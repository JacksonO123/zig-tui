pub const ScreenType = enum {
    Main,
    Alternate,
};

pub const Config = struct {
    screenType: ScreenType = .Main,
};
