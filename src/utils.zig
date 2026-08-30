pub const Pos = struct {
    const Self = @This();

    x: u16 = 0,
    y: u16 = 0,

    pub fn appendOffset(self: Self, other: Self) Self {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }
};

pub const Size = struct {
    height: u16 = 0,
    width: u16 = 0,
};

pub fn lerp(a: i64, b: i64, t: f64) i64 {
    return a + @as(i64, @intFromFloat(@as(f64, @floatFromInt(b - a)) * t));
}
