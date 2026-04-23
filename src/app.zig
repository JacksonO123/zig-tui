const std = @import("std");
const Writer = std.Io.Writer;

const config = @import("config.zig");
const sequences = @import("sequences.zig");
const styles = @import("styles.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn renderUI(terminal: *terminalMod.Terminal) !ui.UIElement {
    // const widthText = try std.fmt.allocPrint(terminal.allocator, "w: {d}", .{terminal.size.col});
    // const heightText = try std.fmt.allocPrint(terminal.allocator, "h: {d}", .{terminal.size.row});

    // var wBox = ui.Text.fromConstText(widthText);
    // _ = wBox.styles.border(.Rounded).paddingX(1).italic();

    // var hBox = ui.Text.fromConstText(heightText);
    // _ = hBox.styles.underline().bold().border(.Square);

    // const layout = try ui.Layout.fromElements(
    //     terminal.allocator,
    //     &[_]ui.UIElement{ wBox, hBox },
    //     if (terminal.size.col % 2 == 0) .Vertical else .Horizontal,
    // );

    // return layout;

    _ = terminal;
    var box = ui.Text.fromConstText("");
    _ = box.styles.border(.Rounded);
    return box;
}

pub const mockConfig: config.Config = .{
    .fullscreen = false,
};
