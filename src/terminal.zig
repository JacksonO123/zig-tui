const std = @import("std");
const Allocator = std.mem.Allocator;

const logMod = @import("logger.zig");

const globalState = &@import("global.zig").globalState;

pub fn Terminal(comptime ModelType: type) type {
    return struct {
        const Self = @This();

        renderAlloc: Allocator,
        gpa: Allocator,
        io: std.Io,
        model: *ModelType,
        logger: *logMod.Logger,

        pub fn init(
            allocator: Allocator,
            io: std.Io,
            model: *ModelType,
            gpa: Allocator,
            logger: *logMod.Logger,
        ) Self {
            return .{
                .renderAlloc = allocator,
                .gpa = gpa,
                .io = io,
                .model = model,
                .logger = logger,
            };
        }

        pub fn stateChanged(self: *Self) void {
            if (globalState.rendering) {
                globalState.needsRerender = true;
            } else {
                globalState.eventUtil.event.set(self.io);
            }
        }
    };
}
