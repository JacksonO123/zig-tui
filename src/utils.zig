const std = @import("std");

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

pub fn indexOfStringInArray(stringArr: []const []const u8, value: []const u8) ?usize {
    for (stringArr, 0..) |string, index| {
        if (std.mem.eql(u8, string, value)) return index;
    }

    return null;
}

pub fn stringArrContains(stringArr: []const []const u8, value: []const u8) bool {
    return indexOfStringInArray(stringArr, value) != null;
}

pub fn removeFromStringArrayList(list: *std.ArrayList([]const u8), value: []const u8) void {
    const index = indexOfStringInArray(list.items, value);
    list.swapRemove(index);
}
