const std = @import("std");
const Allocator = std.mem.Allocator;

const backBufferMod = @import("back_buffer.zig");
const configMod = @import("config.zig");
const terminalMod = @import("terminal.zig");
const utils = @import("utils.zig");

pub const RenderContext = struct {
    const Self = @This();

    config: configMod.Config,
    terminal: *terminalMod.Terminal,
    backBuffer: backBufferMod.BackBuffer,
    rowOffset: i32 = 1,

    pub inline fn init(
        allocator: Allocator,
        terminal: *terminalMod.Terminal,
        config: configMod.Config,
        size: utils.WinSize,
    ) !Self {
        return .{
            .terminal = terminal,
            .config = config,
            .backBuffer = try backBufferMod.BackBuffer.initFromConfig(allocator, config, size),
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.backBuffer.deinit(allocator);
    }
};
