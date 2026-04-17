const std = @import("std");

pub const WinSize = struct { row: u16, col: u16 };

pub fn getWinSize() !WinSize {
    var winsize = std.posix.winsize{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };
    const fd = std.fs.File.stdout().handle;
    const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (std.posix.errno(err) != .SUCCESS) {
        return error.IoctlFailed;
    }
    return .{ .row = winsize.row, .col = winsize.col };
}
