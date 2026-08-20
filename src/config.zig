const types = @import("types.zig");

pub const ScreenType = enum {
    Main,
    Alternate,
};

const CompatibleScreenType = types.setEnumBackingInt(ScreenType, c_int);

pub const Config = struct {
    screenType: ScreenType = .Main,
    rightPadding: ?u16 = null,
};

pub const CompatibleConfig =
    types.setStructLayoutAndBackingInt(
        types.changeFieldType(
            Config,
            "screenType",
            CompatibleScreenType,
        ),
        .@"extern",
        null,
    );
