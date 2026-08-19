const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Logger = struct {
    const Self = @This();
    const LOG_FILE_NAME = "log.txt";

    const LogLevels = enum {
        Log,
        Warning,
        Error,

        pub fn toString(self: @This()) []const u8 {
            return switch (self) {
                .Log => "LOG",
                .Warning => "WARNING",
                .Error => "ERROR",
            };
        }
    };

    arena: std.heap.ArenaAllocator,
    fileWriter: std.Io.File.Writer,
    io: std.Io,

    pub fn init(allocator: Allocator, io: std.Io) !Self {
        const logFile = try initLogFile(io);
        const len = try logFile.length(io);
        var writer = logFile.writer(io, &.{});
        try writer.seekTo(len);

        const arena = std.heap.ArenaAllocator.init(allocator);

        return .{
            .io = io,
            .arena = arena,
            .fileWriter = writer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.fileWriter.flush() catch {};
    }

    fn initLogFile(io: std.Io) !std.Io.File {
        return try std.Io.Dir.cwd().createFile(io, LOG_FILE_NAME, .{ .truncate = false });
    }

    pub fn logBufPrint(
        self: *Self,
        bufSize: comptime_int,
        comptime fmtString: []const u8,
        args: anytype,
    ) !void {
        try self.logLevelBufPrint(.Log, bufSize, fmtString, args);
    }

    pub fn log(self: *Self, msg: []const u8) !void {
        try self.logLevel(.Log, msg);
    }

    pub fn logLevelBufPrint(
        self: *Self,
        level: LogLevels,
        bufSize: comptime_int,
        comptime fmtString: []const u8,
        args: anytype,
    ) !void {
        const argsType = @typeInfo(@TypeOf(args));
        if (argsType != .@"struct" or !argsType.@"struct".is_tuple) {
            @compileError("Expected tuple for args");
        }

        var buf: [bufSize]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, fmtString, args);
        try self.logLevel(level, str);
    }

    pub fn logLevel(self: *Self, level: LogLevels, msg: []const u8) !void {
        var writer = &self.fileWriter.interface;

        const allocator = self.arena.allocator();
        defer _ = self.arena.reset(.retain_capacity);
        defer writer.flush() catch {};

        const fmtString = try std.fmt.allocPrint(
            allocator,
            "[{s}] ({s}): {s}\n",
            .{ level.toString(), try getCurrentTimeStr(allocator, self.io), msg },
        );
        try writer.writeAll(fmtString);
    }

    fn getCurrentTimeStr(allocator: Allocator, io: std.Io) ![]const u8 {
        const epoch_seconds = std.Io.Clock.now(.real, io);
        const epoch_day_seconds = std.time.epoch.EpochSeconds{
            .secs = @intCast(epoch_seconds.toSeconds()),
        };
        const day_seconds = epoch_day_seconds.getDaySeconds();
        const epoch_day = epoch_day_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return std.fmt.allocPrint(
            allocator,
            "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                day_seconds.getHoursIntoDay(),
                day_seconds.getMinutesIntoHour(),
                day_seconds.getSecondsIntoMinute(),
            },
        );
    }
};
