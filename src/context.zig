const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const backBufferMod = @import("back_buffer.zig");
const configMod = @import("config.zig");
const frontBufferMod = @import("front_buffer.zig");
const sequences = @import("sequences.zig");
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
        writer: *Writer,
    ) !Self {
        var terminalArena = std.heap.ArenaAllocator.init(globalArena);
        const terminal = try terminalMod.Terminal.init(terminalArena.allocator(), config, writer);

        return .{
            .terminalArena = terminalArena,
            .terminal = terminal,
            .config = config,
            .backBuffer = try backBufferMod.BackBuffer.init(allocator, terminal.size),
            .frontBuffer = .empty,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator, writer: *Writer) void {
        self.backBuffer.deinit(allocator);
        self.frontBuffer.deinit(allocator);
        self.terminal.deinit(writer);
    }

    pub fn onTerminalResize(self: *Self, size: utils.Size) !void {
        self.terminal.size = size;
        self.state.forceReRender = true;
    }

    pub fn prepareForReRender(self: *Self) void {
        _ = self.terminalArena.reset(.retain_capacity);
    }
};
