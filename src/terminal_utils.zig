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

const PollEvents = enum(u8) {
    Resize = 0b1,
    Stdin = 0b10,
    StateChange = 0b100,
};

pub const EventData = struct {
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
    stdinPollFd: std.posix.pollfd,
    eventArena: std.heap.ArenaAllocator,
    renderArena: std.heap.ArenaAllocator,

    pub fn init(gpa: Allocator, config: configMod.Config, writer: *Writer) !Self {
        const eventArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const renderArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        const size = try getTermSize(config);
        if (contextMod.debugConfig.setBehavior) {
            try setTermBehavior(config, writer);
        }

        const terminalEvent = try gpa.create(std.Io.Event);
        terminalEvent.* = .unset;

        contextMod.globalState.terminalEvent = terminalEvent;

        initResizeEvent();
        const stdinFd = std.Io.File.stdin().handle;
        const stdinPollFd: std.posix.pollfd = .{
            .fd = stdinFd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        };

        return .{
            .size = size,
            .stdinPollFd = stdinPollFd,
            .eventArena = eventArena,
            .renderArena = renderArena,
        };
    }

    pub fn deinit(self: *Self, gpa: Allocator, config: configMod.Config, writer: *Writer) void {
        gpa.destroy(self.terminalEvent);
        self.eventArena.deinit();
        self.renderArena.deinit();
        deinitTermBehavior(config, writer) catch {};
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
        var threadedIo = std.Io.Threaded.init_single_threaded;
        contextMod.globalState.terminalEvent.set(threadedIo.io());
    }

    pub fn pollEvents(self: *Self, io: std.Io, timeout: i32) !struct { EventData, []const u8 } {
        const stdinFd = std.Io.File.stdin().handle;
        _ = stdinFd;

        _ = self.eventArena.reset(.retain_capacity);
        const allocator = self.eventArena.allocator();
        _ = allocator;
        contextMod.globalState.terminalEvent.waitTimeout(io, timeout);
        // _ = try std.posix.poll(@ptrCast(&self.stdinPollFd), timeout);

        var eventData = EventData.init();
        // var readData: []const u8 = &.{};
        const readData: []const u8 = &.{};

        if (contextMod.globalState.eventStatus.resize) {
            contextMod.globalState.eventStatus.resize = false;
            eventData.append(.Resize);
        }

        // if (pollFdHasInEvent(self.stdinPollFd)) a: {
        //     var buf: [64]u8 = undefined;
        //     const bytesRead = std.posix.read(stdinFd, &buf) catch |err| switch (err) {
        //         error.WouldBlock => break :a,
        //         else => return err,
        //     };

        //     eventData.append(.Stdin);

        //     if (bytesRead == 0) break :a;

        //     const clonedData = try allocator.dupe(u8, buf[0..bytesRead]);
        //     readData = clonedData;
        // }

        if (contextMod.globalState.eventStatus.stateChange) {
            contextMod.globalState.eventStatus.stateChange = false;
            eventData.append(.StateChange);
        }

        return .{ eventData, readData };
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
