const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const configMod = @import("config.zig");
const contextMod = @import("context.zig");
const sequences = @import("sequences.zig");
const types = @import("types.zig");

pub const Size = struct {
    height: u16 = 0,
    width: u16 = 0,
};

pub const Pos = struct {
    x: u16 = 0,
    y: u16 = 0,
};

pub const WriteFds = struct {
    resize: std.posix.fd_t,
    stateChange: std.posix.fd_t,
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

pub fn setFdAsNonblocking(fd: std.posix.fd_t) !void {
    const rawFlags = std.c.fcntl(fd, std.c.F.GETFL);
    if (rawFlags < 0) return error.FcntlFailed;
    var o: std.c.O = @bitCast(rawFlags);
    o.NONBLOCK = true;
    const newFlags: c_int = @bitCast(o);
    if (std.c.fcntl(fd, std.c.F.SETFL, newFlags) < 0) return error.FcntlFailed;
}

pub fn getTermSize(config: configMod.Config) !Size {
    var winSize: std.posix.winsize = undefined;
    const fd = std.Io.File.stdout().handle;
    const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winSize));
    if (std.posix.errno(err) != .SUCCESS) {
        return error.IoctlFailed;
    }
    return .{
        .height = winSize.row - @as(u8, if (config.screenType == .Main) 1 else 0),
        .width = winSize.col,
    };
}

pub fn pollFdHasInEvent(fd: std.posix.pollfd) bool {
    return (fd.revents & std.posix.POLL.IN) != 0;
}

pub fn calculateRightPadding(config: configMod.Config) u16 {
    return config.rightPadding orelse @as(u16, if (config.screenType == .Main) 1 else 0);
}

fn initPipeFds() !PollEventPipeFds {
    var pipeFds: [2]std.posix.fd_t = undefined;
    if (std.c.pipe(&pipeFds) < 0) return error.PipeFailed;
    try setFdAsNonblocking(pipeFds[0]);
    try setFdAsNonblocking(pipeFds[1]);
    return .{ .read = pipeFds[0], .write = pipeFds[1] };
}

fn setTermBehavior(config: configMod.Config, writer: *Writer) !void {
    if (config.screenType == .Alternate) {
        try sequences.enableAlternateScreen(writer);
    }

    try enableRawMode();
    try sequences.hideCursor(writer);

    if (config.screenType == .Main) {
        try sequences.disableAutoWrap(writer);
    }
}

fn deinitTermBehavior(config: configMod.Config, writer: *Writer) !void {
    if (config.screenType == .Main) {
        try sequences.enableAutoWrap(writer);
    }

    try sequences.showCursor(writer);
    disableRawMode();

    if (config.screenType == .Alternate) {
        try sequences.disableAlternateScreen(writer);
    }

    try writer.flush();
}

const PollEventPipeFds = struct {
    read: std.posix.fd_t,
    write: std.posix.fd_t,
};

const PollEventsCollectionAllFds = struct {
    resize: PollEventPipeFds,
    stateChange: PollEventPipeFds,
};

const PollEventsCollectionReadFds = types.structFieldsToType(
    types.appendFieldToStruct(
        PollEventsCollectionAllFds,
        .{
            .name = "stdin",
            .type = void,
            .attributes = .{
                .@"comptime" = false,
                .@"align" = null,
                .default_value_ptr = null,
            },
        },
    ),
    std.posix.fd_t,
);

const PollEventsCollectionPollFds = types.structFieldsToType(
    PollEventsCollectionReadFds,
    std.posix.pollfd,
);

const PollEvents = enum(u8) {
    Resize = 0b1,
    Stdin = 0b10,
    StateChange = 0b100,
};

pub const PollEventData = struct {
    const Self = @This();

    data: @typeInfo(PollEvents).@"enum".tag_type,

    pub fn init() Self {
        return .{ .data = 0 };
    }

    pub fn includes(self: Self, flag: PollEvents) bool {
        return self.data & @intFromEnum(flag) != 0;
    }

    pub fn append(self: *Self, flag: PollEvents) void {
        self.data |= @intFromEnum(flag);
    }
};

pub const TerminalUtils = struct {
    const Self = @This();

    size: Size,
    pollFds: PollEventsCollectionAllFds,
    pollEventData: PollEventsCollectionPollFds,
    pollArena: std.heap.ArenaAllocator,
    renderArena: std.heap.ArenaAllocator,

    pub fn init(config: configMod.Config, writer: *Writer) !Self {
        const pollArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const renderArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        const size = try getTermSize(config);
        if (contextMod.debugConfig.setBehavior) {
            try setTermBehavior(config, writer);
        }

        const resizeFds = try initPipeFds();
        const stateChangeFds = try initPipeFds();

        contextMod.globalState.writeFds = .{
            .resize = resizeFds.write,
            .stateChange = stateChangeFds.write,
        };

        initResizeEvent();
        const stdinFd = std.Io.File.stdin().handle;
        const pollFds: PollEventsCollectionReadFds = .{
            .stdin = stdinFd,
            .resize = resizeFds.read,
            .stateChange = stateChangeFds.read,
        };

        const pollEventData = pollFdsToEventData(pollFds);

        const pollPipeFds = PollEventsCollectionAllFds{
            .resize = resizeFds,
            .stateChange = stateChangeFds,
        };

        return .{
            .size = size,
            .pollFds = pollPipeFds,
            .pollEventData = pollEventData,
            .pollArena = pollArena,
            .renderArena = renderArena,
        };
    }

    pub fn deinit(self: *Self, config: configMod.Config, writer: *Writer) void {
        self.pollArena.deinit();
        self.renderArena.deinit();
        self.deinitPollEvents();
        deinitTermBehavior(config, writer) catch {};
    }

    fn pollFdsToEventData(readFds: PollEventsCollectionReadFds) PollEventsCollectionPollFds {
        var pollFds: PollEventsCollectionPollFds = undefined;

        inline for (@typeInfo(PollEventsCollectionReadFds).@"struct".fields) |field| {
            @field(pollFds, field.name) = .{
                .fd = @field(readFds, field.name),
                .events = std.posix.POLL.IN,
                .revents = 0,
            };
        }

        return pollFds;
    }

    fn initResizeEvent() void {
        var action: std.posix.Sigaction = .{
            .handler = .{ .handler = sigWinchHandler },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.WINCH, &action, null);
    }

    fn sigWinchHandler(sig: std.c.SIG) align(1) callconv(.c) void {
        _ = sig;
        const byte: u8 = 1;
        _ = std.c.write(contextMod.globalState.writeFds.resize, @ptrCast(&byte), 1);
    }

    fn deinitPollEvents(self: Self) void {
        inline for (@typeInfo(PollEventsCollectionAllFds).@"struct".fields) |field| {
            const fds = @field(self.pollFds, field.name);
            _ = std.c.close(fds.read);
            _ = std.c.close(fds.write);
        }
    }

    pub fn pollEvents(self: *Self, timeout: i32) !struct { PollEventData, []const u8 } {
        const stdinFd = std.Io.File.stdin().handle;

        _ = self.pollArena.reset(.retain_capacity);
        const allocator = self.pollArena.allocator();
        _ = try std.posix.poll(@ptrCast(&self.pollEventData), timeout);

        var pollData = PollEventData.init();
        var readData: []const u8 = &.{};

        if (pollFdHasInEvent(self.pollEventData.resize)) {
            var drainBuf: [64]u8 = undefined;
            while (true) {
                _ = std.posix.read(self.pollFds.resize.read, &drainBuf) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => return err,
                };
            }
            pollData.append(.Resize);
        }

        if (pollFdHasInEvent(self.pollEventData.stdin)) a: {
            var buf: [64]u8 = undefined;
            const bytesRead = std.posix.read(stdinFd, &buf) catch |err| switch (err) {
                error.WouldBlock => break :a,
                else => return err,
            };

            pollData.append(.Stdin);

            if (bytesRead == 0) break :a;

            const clonedData = try allocator.dupe(u8, buf[0..bytesRead]);
            readData = clonedData;
        }

        if (pollFdHasInEvent(self.pollEventData.stateChange)) {
            var buf: [64]u8 = undefined;
            while (true) {
                _ = std.posix.read(
                    self.pollFds.stateChange.read,
                    &buf,
                ) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => return err,
                };
            }

            pollData.append(.StateChange);
        }

        return .{ pollData, readData };
    }

    pub fn onTerminalResize(
        self: *Self,
        config: configMod.Config,
        state: *contextMod.RenderState,
        size: Size,
    ) void {
        self.size = size;
        if (config.screenType == .Main and size.height < state.rowOffset) {
            state.rowOffset = 1;
        }
        state.forceFullRender = true;
    }

    pub fn prepareForReRender(self: *Self) void {
        _ = self.renderArena.reset(.retain_capacity);
    }
};
