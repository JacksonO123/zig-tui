const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const backBufferMod = @import("back_buffer.zig");
const contextMod = @import("context.zig");
const sequences = @import("sequences.zig");
const stylesMod = @import("styles.zig");
const utils = @import("utils.zig");

pub const FrontBuffer = struct {
    const Self = @This();

    buffer: std.ArrayList(backBufferMod.BufferChar) = .empty,
    rendering: stylesMod.SimpleDataStyle = .{},

    pub const empty: Self = .{};
};
