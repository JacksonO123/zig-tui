const std = @import("std");
const Writer = std.Io.Writer;

const sequences = @import("sequences.zig");
const terminalMod = @import("terminal.zig");
const utils = @import("utils.zig");
const ui = @import("ui.zig");

pub fn renderUI(
    terminal: *terminalMod.Terminal,
    size: utils.WinSize,
) !void {
    _ = size;
    const el = ui.UIElement{ .Text = "some text here\n" };
    try terminal.appendElement(el);

    const el2 = ui.UIElement{ .Text = "more text\n" };
    try terminal.appendElement(el2);
}
