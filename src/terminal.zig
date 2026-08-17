const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const configMod = @import("config.zig");
const sequences = @import("sequences.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const PollEventPipeFds = [2]std.posix.fd_t;
const PollEventsCollectionAllFds = struct {
    resize: PollEventPipeFds,
    stateChange: PollEventPipeFds,
};

const PollEventsCollectionReadFds = utils.structFieldsToType(
    utils.appendFieldToStruct(
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

const PollEventsCollectionPollFds = utils.structFieldsToType(PollEventsCollectionReadFds, std.posix.pollfd);

const PollEventsPollFdsArr = [@typeInfo(PollEventsCollectionPollFds).@"struct".fields.len]std.posix.pollfd;
const PollFdsDataIndices = utils.structFieldsToType(PollEventsCollectionPollFds, usize);
var pollFdsDataIndices: PollFdsDataIndices = undefined;

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

const WriteFds = struct {
    resize: std.posix.fd_t,
    stateChange: std.posix.fd_t,
};

var writeFds: WriteFds = undefined;

pub const Terminal = struct {
    const Self = @This();

    renderAlloc: Allocator,
    gpa: Allocator,

    pub inline fn init(allocator: Allocator, gpa: Allocator) Self {
        return .{ .renderAlloc = allocator, .gpa = gpa };
    }
};

fn sigWinchHandler(sig: std.c.SIG) align(1) callconv(.c) void {
    _ = sig;
    const byte: u8 = 1;
    _ = std.c.write(writeFds.resize, @ptrCast(&byte), 1);
}

pub const TerminalInfo = struct {
    const Self = @This();

    size: utils.Size,
    pollFds: PollEventsCollectionAllFds,
    pollEventData: PollEventsPollFdsArr,
    pollArena: std.heap.ArenaAllocator,
    renderArena: std.heap.ArenaAllocator,

    pub fn init(allocator: Allocator, config: configMod.Config, writer: *Writer) !Self {
        const pollArena = std.heap.ArenaAllocator.init(allocator);
        const renderArena = std.heap.ArenaAllocator.init(allocator);

        const size = try Self.getTermSize();
        try Self.setTermBehavior(config, writer);

        const resizeFds = try Self.initPipeFds();
        const stateChangeFds = try Self.initPipeFds();
        writeFds = .{
            .resize = resizeFds[1],
            .stateChange = stateChangeFds[1],
        };

        Self.initResizeEvent();
        const stdinFd = std.Io.File.stdin().handle;
        const pollFds: PollEventsCollectionReadFds = .{
            .stdin = stdinFd,
            .resize = resizeFds[0],
            .stateChange = stateChangeFds[0],
        };

        const pollEventData, const pollDataIndices = Self.getPollFds(pollFds);
        pollFdsDataIndices = pollDataIndices;

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

    pub fn deinit(self: *Self, writer: *Writer) void {
        self.deinitPollEvents();
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

    fn setTermBehavior(config: configMod.Config, writer: *Writer) !void {
        try utils.enableRawMode();
        try sequences.hideCursor(writer);
        try sequences.disableAutoWrap(writer);

        if (config.screenType == .Fullscreen) {
            try sequences.setCursorPosAbsolute(1, 1, writer);
            try sequences.clearScreen(writer);
        }
    }

    fn initPipeFds() ![2]std.posix.fd_t {
        var pipeFds: [2]std.posix.fd_t = undefined;
        if (std.c.pipe(&pipeFds) < 0) return error.PipeFailed;
        try utils.setNonblocking(pipeFds[0]);
        try utils.setNonblocking(pipeFds[1]);
        return pipeFds;
    }

    fn getPollFds(readFds: PollEventsCollectionReadFds) struct { PollEventsPollFdsArr, PollFdsDataIndices } {
        var pollFds: PollEventsPollFdsArr = undefined;
        var pollFdsIndices: PollFdsDataIndices = undefined;

        inline for (@typeInfo(PollEventsCollectionReadFds).@"struct".fields, 0..) |field, index| {
            pollFds[index] = .{ .fd = @field(readFds, field.name), .events = std.posix.POLL.IN, .revents = 0 };
            @field(pollFdsIndices, field.name) = index;
        }

        return .{ pollFds, pollFdsIndices };
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
            _ = std.c.close(fds[0]);
            _ = std.c.close(fds[1]);
        }
    }

    fn deinitTermBehavior(writer: *Writer) !void {
        try sequences.showCursor(writer);
        utils.disableRawMode();
        try sequences.enableAutoWrap(writer);
        try writer.flush();
    }

    pub fn pollEvents(self: *Self) !struct { PollEventData, []const u8 } {
        const stdinFd = std.Io.File.stdin().handle;

        _ = self.pollArena.reset(.retain_capacity);
        const allocator = self.pollArena.allocator();
        _ = try std.posix.poll(&self.pollEventData, -1);

        var pollData = PollEventData.init();
        var readData: []const u8 = &.{};

        if ((self.pollEventData[pollFdsDataIndices.resize].revents & std.posix.POLL.IN) != 0) {
            var drainBuf: [64]u8 = undefined;
            while (true) {
                _ = std.posix.read(self.pollFds.resize[0], &drainBuf) catch |err| switch (err) {
                    error.WouldBlock => break,
                    else => return err,
                };
            }
            pollData.append(.Resize);
        }

        if ((self.pollEventData[pollFdsDataIndices.stdin].revents & std.posix.POLL.IN) != 0) a: {
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

        return .{ pollData, readData };
    }
};
