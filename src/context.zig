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
const ui = @import("ui.zig");
const types = @import("types.zig");
const renderer = @import("renderer.zig");
const eventUtils = @import("events/event_utils.zig");
const eventTypes = @import("events/event_types.zig");

const globalState = &@import("global.zig").globalState;

pub const debugConfig = .{
    .setBehavior = true,
    // .setBehavior = false,
};

pub const RenderState = struct {
    rowOffset: u16 = 1,
    forceFullRender: bool = false,
    focusedId: ?[]const u8 = null,
};

pub fn RenderContext(comptime ModelType: type, comptime RegisterEvents: type) type {
    return struct {
        const Self = @This();

        const EventListenerCollection = eventListenersMod.EventListenerCollection(RegisterEvents);

        gpa: Allocator,
        model: *ModelType,
        config: configMod.Config,
        terminal: *terminalMod.Terminal(ModelType, RegisterEvents),
        backBuffer: backBufferMod.BackBuffer,
        frontBuffer: frontBufferMod.FrontBuffer,
        terminalUtils: *terminalUtils.TerminalUtils,
        state: RenderState,
        logger: *logMod.Logger,
        rendered: ?*ui.UIElement = null,
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

            const termUtils = try gpa.create(terminalUtils.TerminalUtils);
            termUtils.* = try terminalUtils.TerminalUtils.init(
                config,
                logger,
                writer,
            );

            const eventListeners = try gpa.create(EventListenerCollection);
            eventListeners.* = try EventListenerCollection.init(termUtils.renderArena.allocator());

            const terminal = try gpa.create(terminalMod.Terminal(ModelType, RegisterEvents));
            terminal.* = terminalMod.Terminal(ModelType, RegisterEvents).init(
                termUtils.renderArena.allocator(),
                io,
                model,
                gpa,
                logger,
                eventListeners,
            );

            const backBuffer = try backBufferMod.BackBuffer.init(gpa, termUtils.size);

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
                .eventListeners = eventListeners,
            };
        }

        pub fn deinit(
            self: *Self,
            writer: *Writer,
        ) void {
            self.gpa.destroy(self.terminalUtils);
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

        pub fn render(
            self: *Self,
            io: std.Io,
            renderUI: renderer.RenderUIFn(ModelType, RegisterEvents),
            writer: *Writer,
        ) !void {
            while (true) {
                var allow = true;
                defer if (allow) globalState.eventUtil.event.reset();

                const pollData, var readData = try self.terminalUtils.pollEvents(
                    io,
                    globalState.needsRerender,
                );
                const neededRerender = globalState.needsRerender;
                globalState.needsRerender = false;

                if (pollData.includes(.Resize)) {
                    const size = try terminalUtils.getTermSize(self.config);
                    self.terminalUtils.onTerminalResize(self.config, &self.state, size);
                    try renderer.handleRender(ModelType, RegisterEvents, self.gpa, @ptrCast(self), renderUI, writer);
                }

                if (pollData.includes(.StateChange) or neededRerender) {
                    try renderer.handleRender(ModelType, RegisterEvents, self.gpa, @ptrCast(self), renderUI, writer);
                }

                if (pollData.includes(.Stdin)) {
                    allow = false;

                    if (readData.len == 0) continue;

                    while (readData.len > 0) {
                        if (eventUtils.handleMouseEvent(readData)) |eventData| {
                            switch (eventData.event.button) {
                                64, 65 => {
                                    const direction: eventTypes.ScrollDirection = switch (eventData.event.button) {
                                        64 => .Up,
                                        65 => .Down,
                                        else => unreachable,
                                    };
                                    const scrollEvent = eventTypes.ScrollEvent{
                                        .direction = direction,
                                        .pos = .{
                                            .x = eventData.event.x,
                                            .y = eventData.event.y,
                                        },
                                    };
                                    try self.emit("scroll", .{scrollEvent});
                                },
                                else => {
                                    const btn: eventTypes.MouseEventButton = switch (eventData.event.button) {
                                        0 => .Left,
                                        2 => .Right,
                                        else => .{
                                            .Other = eventData.event.button,
                                        },
                                    };
                                    const event = eventTypes.MouseButtonEvent{
                                        .button = btn,
                                        .x = eventData.event.x,
                                        .y = eventData.event.y,
                                        .pressed = eventData.event.pressed,
                                    };
                                    try self.emit("mouse-btn", .{event});
                                },
                            }

                            readData = readData[eventData.len..];
                        }

                        if (readData.len == 0) break;

                        for (readData) |byte| {
                            switch (byte) {
                                // ctrl c
                                3,
                                // esc
                                27,
                                => return,
                                else => {},
                            }
                        }

                        try self.emit("stdin", .{readData});
                        readData = &.{};
                    }
                }
            }
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
