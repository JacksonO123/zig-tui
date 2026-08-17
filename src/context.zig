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
const app = @import("app.zig");

pub const GlobalState = struct {
    writeFds: terminalMod.WriteFds,
    needsRerender: bool = true,
    rendering: bool = false,
};

pub var globalState: GlobalState = .{ .writeFds = undefined };

pub const RenderState = struct {
    rowOffset: i32 = 1,
    forceFullRender: bool = false,
};

pub const RenderContext = struct {
    const Self = @This();

    model: *app.Model,
    config: configMod.Config,
    terminal: terminalMod.Terminal,
    backBuffer: backBufferMod.BackBuffer,
    frontBuffer: frontBufferMod.FrontBuffer,
    terminalInfo: terminalMod.TerminalInfo,

    state: RenderState = .{},

    pub inline fn init(
        gpa: Allocator,
        globalArena: Allocator,
        config: configMod.Config,
        model: *app.Model,
        writer: *Writer,
    ) !Self {
        var terminalInfo = try terminalMod.TerminalInfo.init(globalArena, config, writer);
        const terminal = terminalMod.Terminal.init(
            terminalInfo.renderArena.allocator(),
            model,
            gpa,
        );

        return .{
            .terminal = terminal,
            .terminalInfo = terminalInfo,
            .config = config,
            .backBuffer = try backBufferMod.BackBuffer.init(gpa, terminalInfo.size),
            .frontBuffer = .empty,
            .model = model,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator, writer: *Writer) void {
        self.backBuffer.deinit(allocator);
        self.frontBuffer.deinit(allocator);
        self.terminalInfo.deinit(writer);
    }

    pub fn onTerminalResize(self: *Self, size: utils.Size) !void {
        self.terminalInfo.size = size;
        self.state.forceFullRender = true;
    }

    pub fn prepareForReRender(self: *Self) void {
        _ = self.terminalInfo.renderArena.reset(.retain_capacity);
    }
};
