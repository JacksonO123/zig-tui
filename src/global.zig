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

pub fn signalResize() void {
    var threadedIo = std.Io.Threaded.init_single_threaded;
    globalState.eventUtil.flags.resize = true;
    globalState.eventUtil.event.set(threadedIo.io());
}
