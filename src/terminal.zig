const std = @import("std");
const Allocator = std.mem.Allocator;

const contextMod = @import("context.zig");
const logMod = @import("logger.zig");

pub fn Terminal(comptime ModelType: type) type {
    return struct {
        const Self = @This();

        renderAlloc: Allocator,
        gpa: Allocator,
        model: *ModelType,
        logger: *logMod.Logger,

        pub fn init(
            allocator: Allocator,
            model: *ModelType,
            gpa: Allocator,
            logger: *logMod.Logger,
        ) Self {
            return .{
                .renderAlloc = allocator,
                .gpa = gpa,
                .model = model,
                .logger = logger,
            };
        }

        pub fn stateChanged(_: *Self) void {
            if (contextMod.globalState.rendering) {
                contextMod.globalState.needsRerender = true;
            } else {
                const byte: u8 = 1;
                _ = std.c.write(contextMod.globalState.writeFds.stateChange, @ptrCast(&byte), 1);
            }
        }
    };
}
