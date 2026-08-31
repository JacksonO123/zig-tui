const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const builtin = @import("builtin");

const configMod = @import("config.zig");
const contextMod = @import("context.zig");
const logMod = @import("logger.zig");
const platform = @import("platform.zig");
const sequences = @import("sequences.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");
const eventListeners = @import("events/event_listeners.zig");

const globalState = &@import("global.zig").globalState;

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
    Skip,
};

pub const WakeReason = union(WakeReasonVariants) {
    Stdin: std.Io.File.ReadStreamingError!usize,
    Update: std.Io.Cancelable!void,
    Skip: std.Io.Cancelable!void,
};

pub fn waitForUpdate(io: std.Io, event: *std.Io.Event) std.Io.Cancelable!void {
    try event.wait(io);
}

pub fn waitForStdin(io: std.Io, buf: []u8) std.Io.File.ReadStreamingError!usize {
    var buffers = [1][]u8{buf};
    return std.Io.File.stdin().readStreaming(io, &buffers);
}

pub fn waitForSkip(io: std.Io, allowSkip: bool) !void {
    if (allowSkip) {
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    } else {
        var event: std.Io.Event = .unset;
        try event.wait(io);
    }
}

pub const TerminalUtils = struct {
    const Self = @This();

    io: std.Io,
    size: utils.Size,
    logger: *logMod.Logger,
    eventArena: std.heap.ArenaAllocator,
    renderArena: std.heap.ArenaAllocator,
    cursorPos: utils.Pos,

    pub fn init(
        io: std.Io,
        config: configMod.Config,
        logger: *logMod.Logger,
        writer: *Writer,
    ) !Self {
        const eventArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const renderArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        const size = try getTermSize(io, config);
        if (contextMod.debugConfig.setBehavior) {
            try setTermBehavior(io, config, writer);
        }

        try platform.startResizeWatch(io);

        const cursorPos = try getCursorPosition(io, writer);

        return .{
            .io = io,
            .size = size,
            .logger = logger,
            .eventArena = eventArena,
            .renderArena = renderArena,
            .cursorPos = cursorPos,
        };
    }

    pub fn deinit(self: *Self, config: configMod.Config, writer: *Writer) void {
        platform.stopResizeWatch();

        self.eventArena.deinit();
        self.renderArena.deinit();
        deinitTermBehavior(self.io, config, writer) catch {};
    }

    pub fn pollEvents(self: *Self, io: std.Io, allowSkip: bool) !struct { EventData, []const u8 } {
        _ = self.eventArena.reset(.retain_capacity);
        const allocator = self.eventArena.allocator();

        var stdinBuf: [4096]u8 = undefined;

        var results: [3]WakeReason = undefined;
        var select = std.Io.Select(WakeReason).init(io, &results);

        select.async(.Update, waitForUpdate, .{ io, &globalState.eventUtil.event });
        select.async(.Stdin, waitForStdin, .{ io, &stdinBuf });
        select.async(.Skip, waitForSkip, .{ io, allowSkip });

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
            .Skip => |valid| {
                _ = try valid;
                eventData.append(.StateChange);
            },
        }

        return .{ eventData, readData };
    }

    pub fn onTerminalResize(
        self: *Self,
        config: configMod.Config,
        state: *contextMod.RenderState,
        size: utils.Size,
    ) void {
        self.size = size;
        if (config.screenType == .Main and size.height < state.rowOffset) {
            state.rowOffset = 1;
        }
        state.forceFullRender = true;
    }

    pub fn prepareForReRender(
        self: *Self,
        listeners: *eventListeners.EventListenerCollection(void),
        writer: *Writer,
    ) !bool {
        try listeners.removeTemporaryListeners();

        _ = self.renderArena.reset(.retain_capacity);

        const cursorPos = getCursorPosition(self.io, writer) catch |err| {
            if (err == error.InvalidResponse) {
                globalState.needsRerender = true;
                return false;
            }
            return err;
        };
        self.cursorPos = cursorPos;

        return true;
    }
};

pub fn getTermSize(io: std.Io, config: configMod.Config) !utils.Size {
    return processTerminalSize(config, try platform.getTerminalSize(io));
}

fn processTerminalSize(config: configMod.Config, size: utils.Size) utils.Size {
    return .{
        .width = size.width,
        .height = size.height -| @as(u8, if (config.screenType == .Main) 1 else 0),
    };
}

pub fn calculateRightPadding(config: configMod.Config) u16 {
    return config.rightPadding orelse @as(u16, if (config.screenType == .Main) 1 else 0);
}

fn setTermBehavior(io: std.Io, config: configMod.Config, writer: *Writer) !void {
    try platform.enterRawMode(io);

    if (config.screenType == .Alternate) {
        try sequences.enableAlternateScreen(writer);
    }

    try sequences.hideCursor(writer);

    if (config.screenType == .Main) {
        try sequences.disableAutoWrap(writer);
    }

    try sequences.enableMouseReporting(writer);

    try writer.flush();
}

fn deinitTermBehavior(io: std.Io, config: configMod.Config, writer: *Writer) !void {
    if (config.screenType == .Main) {
        try sequences.enableAutoWrap(writer);
    }

    try sequences.showCursor(writer);
    try sequences.disableMouseReporting(writer);

    if (config.screenType == .Alternate) {
        try sequences.disableAlternateScreen(writer);
    }

    try writer.flush();

    platform.exitRawMode(io);
}

fn getCursorPosition(io: std.Io, writer: *Writer) !utils.Pos {
    try writer.writeAll("\x1b[6n");
    try writer.flush();

    var buf: [32]u8 = undefined;
    var index: usize = 0;

    while (index < buf.len) {
        var buffers = [1][]u8{buf[index .. index + 1]};
        const amount = try std.Io.File.stdin().readStreaming(io, &buffers);
        if (amount == 0) return error.UnexpectedEOF;
        if (buf[index] == 'R') {
            index += 1;
            break;
        }
        index += 1;
    }

    const res = buf[0..index];

    if (res.len < 2 or res.len < 6 or res[0] != '\x1b' or res[1] != '[') {
        return error.InvalidResponse;
    }

    const data = res[2 .. res.len - 1];
    var split = std.mem.splitScalar(u8, data, ';');

    const rowStr = split.next() orelse return error.InvalidResponse;
    const colStr = split.next() orelse return error.InvalidResponse;

    const row = std.fmt.parseInt(u16, rowStr, 10) catch return error.InvalidResponse;
    const col = std.fmt.parseInt(u16, colStr, 10) catch return error.InvalidResponse;

    return utils.Pos{ .y = row, .x = col };
}
