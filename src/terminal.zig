const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const configMod = @import("config.zig");
const sequences = @import("sequences.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const ResizeFds = [2]std.posix.fd_t;

const PollFds = struct { stdinFd: std.posix.fd_t, fds: [2]std.posix.pollfd };

const PollEvents = enum(u8) {
    Resize = 0b1,
    Stdin = 0b10,
};

const PollEventData = struct {
    const Self = @This();

    data: @typeInfo(PollEvents).@"enum".tag_type,

    pub fn init() Self {
        return .{ .data = 0 };
    }

    pub fn includes(self: Self, flag: PollEvents) bool {
        return self.data & @intFromEnum(flag) != 0;
    }

    fn append(self: *Self, flag: PollEvents) void {
        self.data |= @intFromEnum(flag);
    }
};

var resizePipeWriteFd: std.posix.fd_t = undefined;

pub const Terminal = struct {
    const Self = @This();

    allocator: Allocator,
    size: utils.Size,
    resizeFds: ResizeFds,
    pollFds: PollFds,
    pollArena: std.heap.ArenaAllocator,

    pub inline fn init(allocator: Allocator, config: configMod.Config, writer: *Writer) !Self {
        const pollArena = std.heap.ArenaAllocator.init(allocator);
        const size = try Self.getTermSize();
        try Self.setTermBehavior(config, writer);
        const resizeFds = try Self.initResizeFd();
        resizePipeWriteFd = resizeFds[1];

        Self.initResizeEvent();
        const pollFds = try Self.getPollFds(resizeFds);

        return .{
            .allocator = allocator,
            .size = size,
            .resizeFds = resizeFds,
            .pollFds = pollFds,
            .pollArena = pollArena,
        };
    }

    pub fn deinit(self: *Self, writer: *Writer) void {
        self.deinitResizeEvent();
        Self.deinitTermBehavior(writer) catch {};
    }

    pub fn getTermSize() !utils.Size {
        var winSize: std.posix.winsize = undefined;
        const fd = std.Io.File.stdout().handle;
        const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winSize));
        if (std.posix.errno(err) != .SUCCESS) {
            return error.IoctlFailed;
        }
        return .{ .height = winSize.row, .width = winSize.col };
    }

    fn getPollFds(resizeFds: ResizeFds) !PollFds {
        const stdinFd = std.Io.File.stdin().handle;
        const pollFds = [_]std.posix.pollfd{
            .{ .fd = stdinFd, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = resizeFds[0], .events = std.posix.POLL.IN, .revents = 0 },
        };
        return .{
            .stdinFd = stdinFd,
            .fds = pollFds,
        };
    }

    fn initResizeFd() !ResizeFds {
        var resizeFds: ResizeFds = undefined;
        if (std.c.pipe(&resizeFds) < 0) return error.PipeFailed;
        try utils.setNonblocking(resizeFds[0]);
        try utils.setNonblocking(resizeFds[1]);
        return resizeFds;
    }

    fn initResizeEvent() void {
        var action: std.posix.Sigaction = .{
            .handler = .{ .handler = sigWinchHandler },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.WINCH, &action, null);
    }

    fn deinitResizeEvent(self: Self) void {
        _ = std.c.close(self.resizeFds[0]);
        _ = std.c.close(self.resizeFds[1]);
    }

    fn setTermBehavior(config: configMod.Config, writer: *Writer) !void {
        try utils.enableRawMode();
        try sequences.hideCursor(writer);
        try sequences.disableAutoWrap(writer);

        if (config.screenType == .Fullscreen) {
            try sequences.setCursorPosAbsolute(1, 1, writer);
            try sequences.clearScreen(writer);
        }
    }

    fn deinitTermBehavior(writer: *Writer) !void {
        try sequences.showCursor(writer);
        utils.disableRawMode();
        try sequences.enableAutoWrap(writer);
        try writer.flush();
    }

    pub fn pollEvents(self: *Self) !struct { PollEventData, []const u8 } {
        _ = self.pollArena.reset(.retain_capacity);
        const allocator = self.pollArena.allocator();
        _ = try std.posix.poll(&self.pollFds.fds, -1);

        var pollData = PollEventData.init();
        var readData: []const u8 = &.{};

        if ((self.pollFds.fds[1].revents & std.posix.POLL.IN) != 0) {
            var drainBuf: [64]u8 = undefined;
            while (true) {
                _ = std.posix.read(self.resizeFds[0], &drainBuf) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => return err,
                };
            }
            pollData.append(.Resize);
        }

        if ((self.pollFds.fds[0].revents & std.posix.POLL.IN) != 0) a: {
            var buf: [64]u8 = undefined;
            const bytesRead = std.posix.read(self.pollFds.stdinFd, &buf) catch |err| switch (err) {
                error.WouldBlock => break :a,
                else => return err,
            };

            pollData.append(.Stdin);

            if (bytesRead == 0) break :a;

            const clonedData = try allocator.dupe(u8, buf[0..bytesRead]);
            readData = clonedData;
        }

        return .{ pollData, readData };
    }
};

fn sigWinchHandler(sig: std.c.SIG) align(1) callconv(.c) void {
    _ = sig;
    const byte: u8 = 1;
    _ = std.c.write(resizePipeWriteFd, @ptrCast(&byte), 1);
}
