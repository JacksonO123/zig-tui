const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const builtin = @import("builtin");

const configMod = @import("config.zig");
const contextMod = @import("context.zig");
const logMod = @import("logger.zig");
const sequences = @import("sequences.zig");
const types = @import("types.zig");

const globalState = &@import("global.zig").globalState;

pub const Size = struct {
    height: u16 = 0,
    width: u16 = 0,
};

pub const Pos = struct {
    x: u16 = 0,
    y: u16 = 0,
};

var savedTermios: ?std.posix.termios = null;

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

pub const WakeReasonVariants = enum {
    Stdin,
    Update,
};

pub const WakeReason = union(WakeReasonVariants) {
    Stdin: std.Io.File.ReadStreamingError!usize,
    Update: std.Io.Cancelable!void,
};

pub fn waitForUpdate(io: std.Io, event: *std.Io.Event) std.Io.Cancelable!void {
    try event.wait(io);
}

pub fn waitForStdin(io: std.Io, buf: []u8) std.Io.File.ReadStreamingError!usize {
    var buffers = [1][]u8{buf};
    return std.Io.File.stdin().readStreaming(io, &buffers);
}

pub const TerminalUtils = struct {
    const Self = @This();

    size: Size,
    logger: *logMod.Logger,
    eventArena: std.heap.ArenaAllocator,
    renderArena: std.heap.ArenaAllocator,

    pub fn init(
        config: configMod.Config,
        logger: *logMod.Logger,
        writer: *Writer,
    ) !Self {
        const eventArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const renderArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        const size = try getTermSize(config);
        if (contextMod.debugConfig.setBehavior) {
            try setTermBehavior(config, writer);
        }

        initResizeEvent();

        return .{
            .size = size,
            .logger = logger,
            .eventArena = eventArena,
            .renderArena = renderArena,
        };
    }

    pub fn deinit(self: *Self, config: configMod.Config, writer: *Writer) void {
        self.eventArena.deinit();
        self.renderArena.deinit();
        deinitTermBehavior(config, writer) catch {};
    }

    fn initResizeEvent() void {
        if (builtin.os.tag != .windows) {
            var action: std.posix.Sigaction = .{
                .handler = .{ .handler = sigWinchHandler },
                .mask = std.posix.sigemptyset(),
                .flags = 0,
            };
            std.posix.sigaction(std.posix.SIG.WINCH, &action, null);
        }
    }

    fn sigWinchHandler(sig: std.c.SIG) align(1) callconv(.c) void {
        _ = sig;
        var threadedIo = std.Io.Threaded.init_single_threaded;
        globalState.eventUtil.flags.resize = true;
        globalState.eventUtil.event.set(threadedIo.io());
    }

    pub fn pollEvents(self: *Self, io: std.Io) !struct { EventData, []const u8 } {
        _ = self.eventArena.reset(.retain_capacity);
        const allocator = self.eventArena.allocator();

        var stdinBuf: [4096]u8 = undefined;

        var results: [2]WakeReason = undefined;
        var select = std.Io.Select(WakeReason).init(io, &results);

        select.async(.Update, waitForUpdate, .{ io, &globalState.eventUtil.event });
        select.async(.Stdin, waitForStdin, .{ io, &stdinBuf });

        const result = try select.await();
        _ = select.cancel();

        var eventData = EventData.init();
        var readData: []const u8 = &.{};

        switch (result) {
            .Stdin => |bytesReadOrError| a: {
                const bytesRead = try bytesReadOrError;
                if (bytesRead == 0) break :a;

                eventData.append(.Stdin);

                const clonedData = try allocator.dupe(u8, stdinBuf[0..bytesRead]);
                readData = clonedData;
            },
            .Update => |valid| {
                _ = try valid;

                if (globalState.eventUtil.flags.resize) {
                    globalState.eventUtil.flags.resize = false;
                    eventData.append(.Resize);
                }

                if (globalState.eventUtil.flags.stateChange) {
                    globalState.eventUtil.flags.stateChange = false;
                    eventData.append(.StateChange);
                }
            },
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

    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
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
    const stdoutHandle = std.Io.File.stdout().handle;
    var row: u16 = 0;
    var col: u16 = 0;

    if (builtin.os.tag == .windows) {
        var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(stdoutHandle, &info) == 0) {
            return error.GetConsoleInfoFailed;
        }

        row = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1);
        col = @intCast(info.srWindow.Right - info.srWindow.Left + 1);
    } else {
        var winSize: std.posix.winsize = undefined;
        const fd = std.Io.File.stdout().handle;
        const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winSize));
        if (std.posix.errno(err) != .SUCCESS) {
            return error.IoctlFailed;
        }
        row = winSize.row;
        col = winSize.col;
    }

    return .{
        .height = row - @as(u8, if (config.screenType == .Main) 1 else 0),
        .width = col,
    };
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
