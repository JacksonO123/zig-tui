const std = @import("std");
const Writer = std.Io.Writer;

const config = @import("config.zig");
const sequences = @import("sequences.zig");
const styles = @import("styles.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn renderUI(terminal: *terminalMod.Terminal) !ui.UIElement {
    var xBox = ui.Text.fromConstText("X");
    _ = xBox.styles.border(.Rounded).paddingX(1).bold();

    var oBox = ui.Text.fromConstText("O");
    oBox.styles = xBox.styles;
    _ = oBox.styles.underline();

    const hLayout1 = try ui.Layout.fromElements(
        terminal.allocator,
        &[_]ui.UIElement{ xBox, oBox, xBox },
        .Horizontal,
    );

    const hLayout2 = try ui.Layout.fromElements(
        terminal.allocator,
        &[_]ui.UIElement{ oBox, xBox, oBox },
        .Horizontal,
    );

    const layout = try ui.Layout.fromElements(
        terminal.allocator,
        &[_]ui.UIElement{ hLayout1, hLayout2, hLayout1 },
        .Vertical,
    );

    return layout;
}

pub const mockConfig: config.Config = .{
    .fullscreen = false,
};
