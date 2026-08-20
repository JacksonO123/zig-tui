const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const configMod = @import("config.zig");
const sequences = @import("sequences.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");
const context = @import("context.zig");
const types = @import("types.zig");

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

pub const WriteFds = struct {
    resize: std.posix.fd_t,
    stateChange: std.posix.fd_t,
};

pub fn Terminal(comptime ModelType: type) type {
    return struct {
        const Self = @This();

        renderAlloc: Allocator,
        gpa: Allocator,
        model: *ModelType,

        pub fn init(
            allocator: Allocator,
            model: *ModelType,
            gpa: Allocator,
        ) Self {
            return .{ .renderAlloc = allocator, .gpa = gpa, .model = model };
        }

        pub fn stateChanged(_: *Self) void {
            if (context.globalState.rendering) {
                context.globalState.needsRerender = true;
            } else {
                const byte: u8 = 1;
                _ = std.c.write(context.globalState.writeFds.stateChange, @ptrCast(&byte), 1);
            }
        }
    };
}

fn sigWinchHandler(sig: std.c.SIG) align(1) callconv(.c) void {
    _ = sig;
    const byte: u8 = 1;
    _ = std.c.write(context.globalState.writeFds.resize, @ptrCast(&byte), 1);
}

pub const TerminalInfo = struct {
    const Self = @This();

    size: utils.Size,
    pollFds: PollEventsCollectionAllFds,
    pollEventData: PollEventsCollectionPollFds,
    pollArena: std.heap.ArenaAllocator,
    renderArena: std.heap.ArenaAllocator,

    pub fn init(config: configMod.Config, writer: *Writer) !Self {
        const pollArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const renderArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        const size = try utils.getTermSize(config);
        try Self.setTermBehavior(config, writer);

        const resizeFds = try Self.initPipeFds();
        const stateChangeFds = try Self.initPipeFds();

        context.globalState.writeFds = .{
            .resize = resizeFds.write,
            .stateChange = stateChangeFds.write,
        };

        Self.initResizeEvent();
        const stdinFd = std.Io.File.stdin().handle;
        const pollFds: PollEventsCollectionReadFds = .{
            .stdin = stdinFd,
            .resize = resizeFds.read,
            .stateChange = stateChangeFds.read,
        };

        const pollEventData = Self.pollFdsToEventData(pollFds);

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
        Self.deinitTermBehavior(config, writer) catch {};
    }

    fn setTermBehavior(config: configMod.Config, writer: *Writer) !void {
        if (config.screenType == .Alternate) {
            try sequences.enableAlternateScreen(writer);
        }

        try utils.enableRawMode();
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
        utils.disableRawMode();

        if (config.screenType == .Alternate) {
            try sequences.disableAlternateScreen(writer);
        }

        try writer.flush();
    }

    fn initPipeFds() !PollEventPipeFds {
        var pipeFds: [2]std.posix.fd_t = undefined;
        if (std.c.pipe(&pipeFds) < 0) return error.PipeFailed;
        try utils.setNonblocking(pipeFds[0]);
        try utils.setNonblocking(pipeFds[1]);
        return .{ .read = pipeFds[0], .write = pipeFds[1] };
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

        if (utils.pollFdHasInEvent(self.pollEventData.resize)) {
            var drainBuf: [64]u8 = undefined;
            while (true) {
                _ = std.posix.read(self.pollFds.resize.read, &drainBuf) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => return err,
                };
            }
            pollData.append(.Resize);
        }

        if (utils.pollFdHasInEvent(self.pollEventData.stdin)) a: {
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

        if (utils.pollFdHasInEvent(self.pollEventData.stateChange)) {
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
};
