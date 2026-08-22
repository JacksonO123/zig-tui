const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const backBufferMod = @import("back_buffer.zig");
const configMod = @import("config.zig");
const eventListenersMod = @import("event_listeners.zig");
const frontBufferMod = @import("front_buffer.zig");
const logMod = @import("logger.zig");
const sequences = @import("sequences.zig");
const terminalMod = @import("terminal.zig");
const terminalUtils = @import("terminal_utils.zig");

pub const debugConfig = .{
    .setBehavior = true,
    // .setBehavior = false,
};

pub const GlobalState = struct {
    writeFds: terminalUtils.WriteFds,
    needsRerender: bool = true,
    rendering: bool = false,
};

pub var globalState: GlobalState = .{ .writeFds = undefined };

pub const RenderState = struct {
    rowOffset: u16 = 1,
    forceFullRender: bool = false,
    size: terminalUtils.Size = .{},
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
        terminalUtils: terminalUtils.TerminalUtils,
        state: RenderState,
        logger: logMod.Logger,
        eventListeners: eventListenersMod.EventListenerCollection,

        pub inline fn init(
            gpa: Allocator,
            io: std.Io,
            config: configMod.Config,
            model: *ModelType,
            writer: *Writer,
        ) !Self {
            var termUtils = try terminalUtils.TerminalUtils.init(config, writer);
            const terminal = terminalMod.Terminal(ModelType).init(
                termUtils.renderArena.allocator(),
                model,
                gpa,
            );
            const logger = try logMod.Logger.init(io);
            const eventListenersCollection = try eventListenersMod.EventListenerCollection.init(gpa);

            return .{
                .gpa = gpa,
                .terminal = terminal,
                .terminalUtils = termUtils,
                .config = config,
                .backBuffer = try backBufferMod.BackBuffer.init(gpa, termUtils.size),
                .frontBuffer = .empty,
                .model = model,
                .logger = logger,
                .eventListeners = eventListenersCollection,
                .state = .{},
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
        }
    };
}

pub fn postInit(
    comptime ModelType: type,
    context: *RenderContext(ModelType),
    writer: *Writer,
) !void {
    if (context.config.screenType == .Alternate) {
        try sequences.clearScreen(writer);
        try writer.flush();
    }

    try context.eventListeners.register(
        "stdin",
        fn (*RenderContext(ModelType), data: []const u8) void,
        .{context},
    );
}
