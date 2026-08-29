const std = @import("std");
const Allocator = std.mem.Allocator;

const eventListenersMod = @import("events/event_listeners.zig");
const logMod = @import("logger.zig");
const terminalUtils = @import("terminal_utils.zig");

const globalState = &@import("global.zig").globalState;

pub fn Terminal(comptime ModelType: type, comptime RegisterEvents: type) type {
    return struct {
        const Self = @This();

        const EventListenerCollection = eventListenersMod.EventListenerCollection(RegisterEvents);

        renderAlloc: Allocator,
        gpa: Allocator,
        io: std.Io,
        model: *ModelType,
        logger: *logMod.Logger,
        listeners: *EventListenerCollection,

        pub fn init(
            allocator: Allocator,
            io: std.Io,
            model: *ModelType,
            gpa: Allocator,
            logger: *logMod.Logger,
            listeners: *EventListenerCollection,
        ) Self {
            return .{
                .renderAlloc = allocator,
                .gpa = gpa,
                .io = io,
                .model = model,
                .logger = logger,
                .listeners = listeners,
            };
        }

        pub fn stateChanged(self: *Self) void {
            if (globalState.rendering) {
                globalState.needsRerender = true;
            } else {
                globalState.eventUtil.flags.stateChange = true;
                globalState.eventUtil.event.set(self.io);
            }
        }

        pub fn emit(self: *Self, comptime name: []const u8, payload: anytype) !void {
            try self.listeners.emit(name, payload);
        }

        /// creates temporary listener
        pub fn on(
            self: *Self,
            comptime name: []const u8,
            baseArgs: anytype,
            comptime handler: anytype,
        ) !void {
            try self.listeners.onTemporary(name, baseArgs, handler);
        }
    };
}
