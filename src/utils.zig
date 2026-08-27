pub const Pos = struct {
    x: u16 = 0,
    y: u16 = 0,
};

pub const Size = struct {
    height: u16 = 0,
    width: u16 = 0,
};

pub fn lerp(a: i64, b: i64, t: f64) i64 {
    return a + @as(i64, @intFromFloat(@as(f64, @floatFromInt(b - a)) * t));
}
