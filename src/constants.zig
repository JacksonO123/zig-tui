const styles = @import("styles.zig");

pub const colors = .{
    .gray = styles.Color{
        .Custom = .{ .r = 117, .g = 117, .b = 117 },
    },
};

const Keys = struct {
    Esc: u8 = 27,
    Backspace: u8 = 127,
};

pub const keys = Keys{};
