const styles = @import("styles.zig");

pub const colors = .{
    .gray = styles.Color{
        .Custom = .{ .r = 117, .g = 117, .b = 117 },
    },
};

const Keys = struct {
    Esc: u8 = 27,
    Backspace: u8 = 127,
    BackspaceAlt: u8 = 8,

    pub fn isBackspace(self: @This(), byte: u8) bool {
        return byte == self.Backspace or byte == self.BackspaceAlt;
    }
};

pub const keys = Keys{};
