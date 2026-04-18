const config = @import("config.zig");
const terminalMod = @import("terminal.zig");

pub const RenderContext = struct {
    const Self = @This();

    terminal: *terminalMod.Terminal,
    config: config.Config = .{},
    rowOffset: i32 = 1,

    pub inline fn init(terminal: *terminalMod.Terminal) Self {
        return .{
            .terminal = terminal,
        };
    }
};
