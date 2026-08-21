const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const backBufferMod = @import("back_buffer.zig");
const configMod = @import("config.zig");
const frontBufferMod = @import("front_buffer.zig");
const logMod = @import("logger.zig");
const terminalMod = @import("terminal.zig");
const utils = @import("utils.zig");
const eventListenersMod = @import("event_listeners.zig");

pub const GlobalState = struct {
    writeFds: terminalMod.WriteFds,
    needsRerender: bool = true,
    rendering: bool = false,
};

pub var globalState: GlobalState = .{ .writeFds = undefined };

pub const RenderState = struct {
    rowOffset: u16 = 1,
    forceFullRender: bool = false,
};

pub fn RenderContext(comptime ModelType: type) type {
    return struct {
        const Self = @This();

        gpa: Allocator,
        model: *ModelType,
        config: configMod.Config,
        terminal: terminalMod.Terminal(ModelType),
        backBuffer: backBufferMod.BackBuffer,
        frontBuffer: frontBufferMod.FrontBuffer,
        terminalInfo: terminalMod.TerminalInfo,
        state: RenderState = .{},
        logger: logMod.Logger,
        eventListeners: eventListenersMod.EventListenerCollection,

        pub inline fn init(
            gpa: Allocator,
            io: std.Io,
            config: configMod.Config,
            model: *ModelType,
            writer: *Writer,
        ) !Self {
            var terminalInfo = try terminalMod.TerminalInfo.init(config, writer);
            const terminal = terminalMod.Terminal(ModelType).init(
                terminalInfo.renderArena.allocator(),
                model,
                gpa,
            );

            const logger = try logMod.Logger.init(io);

            return .{
                .gpa = gpa,
                .terminal = terminal,
                .terminalInfo = terminalInfo,
                .config = config,
                .backBuffer = try backBufferMod.BackBuffer.init(gpa, terminalInfo.size),
                .frontBuffer = .empty,
                .model = model,
                .logger = logger,
                .eventListeners = eventListenersMod.EventListenerCollection.init(),
            };
        }

        pub fn deinit(
            self: *Self,
            writer: *Writer,
        ) void {
            self.backBuffer.deinit(self.gpa);
            self.frontBuffer.deinit(self.gpa);
            self.terminalInfo.deinit(self.config, writer);
        }
    };
}
