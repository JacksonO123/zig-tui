const std = @import("std");
const Allocator = std.mem.Allocator;

const backBufferMod = @import("back_buffer.zig");

pub const WinSize = struct { row: u16, col: u16 };
pub const Pos = WinSize;

pub fn getWinSize() !WinSize {
    var winsize: std.posix.winsize = undefined;
    const fd = std.Io.File.stdout().handle;
    const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (std.posix.errno(err) != .SUCCESS) {
        return error.IoctlFailed;
    }
    return .{ .row = winsize.row, .col = winsize.col };
}

pub fn ensureBufferCapacity(
    allocator: Allocator,
    buf: *std.ArrayList(backBufferMod.BufferChar),
    capacity: usize,
) !void {
    if (capacity <= buf.items.len) return;

    if (capacity > buf.capacity) {
        try buf.ensureTotalCapacity(allocator, capacity);
    }

    const prevLen = buf.items.len;
    buf.items.len = capacity;
    @memset(buf.items[prevLen..], .{ .data = .{ .bytes = "    ".*, .len = 1 } });
}
