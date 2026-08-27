const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const backBufferMod = @import("back_buffer.zig");
const configMod = @import("config.zig");
const eventListenersMod = @import("events/event_listeners.zig");
const frontBufferMod = @import("front_buffer.zig");
const logMod = @import("logger.zig");
const sequences = @import("sequences.zig");
const terminalMod = @import("terminal.zig");
const terminalUtils = @import("terminal_utils.zig");
const utils = @import("utils.zig");

pub const debugConfig = .{
    .setBehavior = true,
    // .setBehavior = false,
};

pub const RenderState = struct {
    rowOffset: u16 = 1,
    forceFullRender: bool = false,
    size: utils.Size = .{},
};

pub fn RenderContext(comptime ModelType: type, comptime RegisterEvents: type) type {
    return struct {
        const Self = @This();

        const EventListenerCollection = eventListenersMod.EventListenerCollection(RegisterEvents);

        gpa: Allocator,
        model: *ModelType,
        config: configMod.Config,
        terminal: *terminalMod.Terminal(ModelType),
        backBuffer: backBufferMod.BackBuffer,
        frontBuffer: frontBufferMod.FrontBuffer,
        terminalUtils: terminalUtils.TerminalUtils,
        state: RenderState,
        logger: *logMod.Logger,
        eventListeners: *EventListenerCollection,

        pub inline fn init(
            gpa: Allocator,
            io: std.Io,
            config: configMod.Config,
            model: *ModelType,
            writer: *Writer,
        ) !Self {
            const logger = try gpa.create(logMod.Logger);
            logger.* = try logMod.Logger.init(io);

            var termUtils = try terminalUtils.TerminalUtils.init(config, logger, writer);
            const terminal = try gpa.create(terminalMod.Terminal(ModelType));
            terminal.* = terminalMod.Terminal(ModelType).init(
                termUtils.renderArena.allocator(),
                io,
                model,
                gpa,
                logger,
            );

            const backBuffer = try backBufferMod.BackBuffer.init(gpa, termUtils.size);

            const eventListenersPtr = try gpa.create(EventListenerCollection);
            eventListenersPtr.* = try EventListenerCollection.init(gpa);

            return .{
                .gpa = gpa,
                .terminal = terminal,
                .terminalUtils = termUtils,
                .config = config,
                .backBuffer = backBuffer,
                .frontBuffer = .empty,
                .model = model,
                .logger = logger,
                .state = .{},
                .eventListeners = eventListenersPtr,
            };
        }

        pub fn deinit(
            self: *Self,
            writer: *Writer,
        ) void {
            self.backBuffer.deinit(self.gpa);
            self.frontBuffer.deinit(self.gpa);
            self.terminalUtils.deinit(self.config, writer);
            self.eventListeners.deinit();
            self.gpa.destroy(self.eventListeners);
            self.gpa.destroy(self.logger);
            self.gpa.destroy(self.terminal);
        }

        pub fn on(
            self: *Self,
            comptime name: []const u8,
            baseArgs: anytype,
            comptime handler: anytype,
        ) !void {
            try self.eventListeners.on(name, baseArgs, handler);
        }

        pub fn emit(self: *Self, comptime name: []const u8, payload: anytype) !void {
            try self.eventListeners.emit(name, payload);
        }
    };
}

pub fn postInit(
    context: *RenderContext(anyopaque, void),
    writer: *Writer,
) !void {
    if (context.config.screenType == .Alternate) {
        try sequences.clearScreen(writer);
        try writer.flush();
    }
}
