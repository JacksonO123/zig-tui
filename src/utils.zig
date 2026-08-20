const std = @import("std");
const Allocator = std.mem.Allocator;

const backBufferMod = @import("back_buffer.zig");
const configMod = @import("config.zig");
const contextMod = @import("context.zig");
const RenderContext = contextMod.RenderContext;

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

pub fn structFieldsToType(comptime Struct: type, comptime ToType: type) type {
    const structTypeBefore = @typeInfo(Struct);
    if (structTypeBefore != .@"struct") @compileError("Expected struct for index transform");
    const structType = structTypeBefore.@"struct";

    var fieldNames: [structType.fields.len][]const u8 = undefined;
    var fieldTypes: [structType.fields.len]type = undefined;
    var fieldAttributes: [structType.fields.len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (structType.fields, 0..) |field, index| {
        fieldNames[index] = field.name;
        fieldTypes[index] = ToType;
        fieldAttributes[index] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
    }

    return @Struct(
        structType.layout,
        structType.backing_integer,
        &fieldNames,
        &fieldTypes,
        &fieldAttributes,
    );
}

pub fn appendFieldToStruct(
    comptime Struct: type,
    comptime newField: struct {
        name: []const u8,
        type: type,
        attributes: std.builtin.Type.StructField.Attributes,
    },
) type {
    const structTypeBefore = @typeInfo(Struct);
    if (structTypeBefore != .@"struct") @compileError("Expected struct for index transform");
    const structType = structTypeBefore.@"struct";

    var fieldNames: [structType.fields.len + 1][]const u8 = undefined;
    var fieldTypes: [structType.fields.len + 1]type = undefined;
    var fieldAttributes: [structType.fields.len + 1]std.builtin.Type.StructField.Attributes = undefined;

    inline for (structType.fields, 0..) |field, index| {
        fieldNames[index] = field.name;
        fieldTypes[index] = field.type;
        fieldAttributes[index] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
    }

    fieldNames[fieldNames.len - 1] = newField.name;
    fieldTypes[fieldTypes.len - 1] = newField.type;
    fieldAttributes[fieldAttributes.len - 1] = newField.attributes;

    return @Struct(
        structType.layout,
        structType.backing_integer,
        &fieldNames,
        &fieldTypes,
        &fieldAttributes,
    );
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

pub fn readCursorPositionReport() !u16 {
    var state: enum { esc, bracket, row, col } = .esc;
    var rowVal: u16 = 0;
    var colVal: u16 = 0;

    var fds = [_]std.posix.pollfd{.{
        .fd = std.posix.STDIN_FILENO,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    const timeoutMs: i32 = 200; // terminals reply near-instantly; bail rather than hang forever

    while (true) {
        const ready = try std.posix.poll(&fds, timeoutMs);
        if (ready == 0) return error.UnexpectedEof; // no reply in time

        var byte: [1]u8 = undefined;
        const n = std.posix.read(std.posix.STDIN_FILENO, &byte) catch |err| switch (err) {
            error.WouldBlock => continue, // not actually ready yet, poll again
            else => return err,
        };
        if (n == 0) return error.UnexpectedEof;
        const c = byte[0];

        switch (state) {
            .esc => if (c == 0x1b) {
                state = .bracket;
            },
            .bracket => state = if (c == '[') .row else .esc,
            .row => switch (c) {
                '0'...'9' => rowVal = rowVal *% 10 +% (c - '0'),
                ';' => state = .col,
                else => return error.MalformedResponse,
            },
            .col => switch (c) {
                '0'...'9' => colVal = colVal *% 10 +% (c - '0'),
                'R' => {
                    return rowVal;
                },
                else => return error.MalformedResponse,
            },
        }
    }
}
