const std = @import("std");
const Writer = std.Io.Writer;

const config = @import("config.zig");
const sequences = @import("sequences.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn renderUI(terminal: *terminalMod.Terminal) !ui.UIElement {
    const el = ui.Text.fromConstText("some text\nhere");
    const el2 = ui.Text.fromConstText("more text");
    const layout = try ui.Layout.fromElements(
        terminal.allocator,
        &[_]ui.UIElement{ el, el2 },
        .Vertical,
    );

    return layout;
}

pub const mockConfig: config.Config = .{
    .fullscreen = false,
};
