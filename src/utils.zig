const std = @import("std");
const Allocator = std.mem.Allocator;

const backBufferMod = @import("back_buffer.zig");

pub const Size = struct {
    height: u16 = 0,
    width: u16 = 0,
};

pub const Pos = struct {
    x: u16 = 0,
    y: u16 = 0,
};

var savedTermios: ?std.posix.termios = null;

pub fn enableRawMode() !void {
    const fd = std.Io.File.stdin().handle;
    const original = try std.posix.tcgetattr(fd);
    savedTermios = original;

    var raw = original;
    raw.iflag.BRKINT = false;
    raw.iflag.ICRNL = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.IXON = false;

    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.IEXTEN = false;
    raw.lflag.ISIG = false;

    raw.oflag.OPOST = false;

    raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

    try std.posix.tcsetattr(fd, .FLUSH, raw);
}

pub fn disableRawMode() void {
    const orig = savedTermios orelse return;
    const fd = std.Io.File.stdin().handle;
    std.posix.tcsetattr(fd, .FLUSH, orig) catch {};
    savedTermios = null;
}

pub fn setNonblocking(fd: std.posix.fd_t) !void {
    const rawFlags = std.c.fcntl(fd, std.c.F.GETFL);
    if (rawFlags < 0) return error.FcntlFailed;
    var o: std.c.O = @bitCast(rawFlags);
    o.NONBLOCK = true;
    const newFlags: c_int = @bitCast(o);
    if (std.c.fcntl(fd, std.c.F.SETFL, newFlags) < 0) return error.FcntlFailed;
}
