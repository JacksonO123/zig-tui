const std = @import("std");
const Allocator = std.mem.Allocator;

const backBufferMod = @import("back_buffer.zig");

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

pub fn getTermSize() !Size {
    var winSize: std.posix.winsize = undefined;
    const fd = std.Io.File.stdout().handle;
    const err = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winSize));
    if (std.posix.errno(err) != .SUCCESS) {
        return error.IoctlFailed;
    }
    return .{ .height = winSize.row, .width = winSize.col };
}

pub fn pollFdHasInEvent(fd: std.posix.pollfd) bool {
    return (fd.revents & std.posix.POLL.IN) != 0;
}
