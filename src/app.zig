const std = @import("std");
const Writer = std.Io.Writer;

const config = @import("config.zig");
const sequences = @import("sequences.zig");
const styles = @import("styles.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn renderUI(terminal: *terminalMod.Terminal) !ui.UIElement {
    var el = ui.Text.fromConstText("some text\nhere");
    _ = el.styles.border(.Rounded).paddingX(1).underline().italic();

    var el2 = ui.Text.fromConstText("more text");
    _ = el2.styles.bold();

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
