const std = @import("std");

const utils = @import("utils.zig");

const GlobalState = struct {
    const Self = @This();

    eventUtil: struct {
        event: std.Io.Event = .is_set,
        flags: struct {
            resize: bool = false,
            stateChange: bool = false,
        } = .{},
    } = .{},
    needsRerender: bool = true,
    rendering: bool = false,
};

pub var globalState: GlobalState = .{};
