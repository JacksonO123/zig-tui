const std = @import("std");

const utils = @import("../utils.zig");

const globalMod = @import("../global.zig");

var savedTermios: ?std.posix.termios = null;

pub fn enterRawMode(io: std.Io) !void {
    _ = io;

    const handle = std.Io.File.stdin().handle;

    const original = try std.posix.tcgetattr(handle);
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

    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;

    try std.posix.tcsetattr(handle, .FLUSH, raw);
}

pub fn exitRawMode(io: std.Io) void {
    _ = io;

    const original = savedTermios orelse return;
    std.posix.tcsetattr(std.Io.File.stdin().handle, .FLUSH, original) catch {};

    savedTermios = null;
}

pub fn getTerminalSize(io: std.Io) !utils.Size {
    _ = io;

    var winSize: std.posix.winsize = undefined;
    const fd = std.Io.File.stdout().handle;
    const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winSize));
    if (std.posix.errno(err) != .SUCCESS) {
        return error.FailedToGetTerminalSize;
    }

    return .{
        .width = winSize.col,
        .height = winSize.row,
    };
}

pub fn startResizeWatch(io: std.Io) !void {
    _ = io;

    var action: std.posix.Sigaction = .{
        .handler = .{ .handler = sigWinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &action, null);
}

pub fn stopResizeWatch() void {}

fn sigWinchHandler(sig: std.c.SIG) align(1) callconv(.c) void {
    _ = sig;
    globalMod.signalResize();
}
