const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const backBufferMod = @import("back_buffer.zig");
const configMod = @import("config.zig");
const frontBufferMod = @import("front_buffer.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub const RenderState = struct {
    rowOffset: i32 = 1,
    forceReRender: bool = false,
};

pub const RenderContext = struct {
    const Self = @This();

    config: configMod.Config,
    terminalArena: std.heap.ArenaAllocator,
    terminal: terminalMod.Terminal,
    backBuffer: backBufferMod.BackBuffer,
    frontBuffer: frontBufferMod.FrontBuffer,

    state: RenderState = .{},

    pub inline fn init(
        allocator: Allocator,
        globalArena: Allocator,
        config: configMod.Config,
        size: utils.WinSize,
    ) !Self {
        var terminalArena = std.heap.ArenaAllocator.init(globalArena);
        const terminal = terminalMod.Terminal.init(terminalArena.allocator(), size);

        return .{
            .terminalArena = terminalArena,
            .terminal = terminal,
            .config = config,
            .backBuffer = try backBufferMod.BackBuffer.init(allocator, size),
            .frontBuffer = .empty,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.backBuffer.deinit(allocator);
        self.frontBuffer.deinit(allocator);
    }

    pub fn onTerminalResize(self: *Self, size: utils.WinSize) !void {
        self.terminal.size = size;
    }
};
