pub const ScreenType = enum {
    Fullscreen,
    Main,
    Alternate,
};

pub const Config = struct {
    screenType: ScreenType = .Main,
};
