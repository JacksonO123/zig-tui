const std = @import("std");
const Writer = std.Io.Writer;

const config = @import("config.zig");
const sequences = @import("sequences.zig");
const styles = @import("styles.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn renderUI(terminal: *terminalMod.Terminal) !ui.UIElement {
    const allocator = terminal.allocator;
    const area: u32 = @as(u32, terminal.size.width) * @as(u32, terminal.size.height);

    const widthText = try std.fmt.allocPrint(allocator, "w: {d}", .{terminal.size.width});
    const heightText = try std.fmt.allocPrint(allocator, "h: {d}", .{terminal.size.height});
    const areaText = try std.fmt.allocPrint(allocator, "area: {d}", .{area});

    var wBox = ui.Text.fromConstText(widthText);
    _ = wBox.styles.border(.Rounded).paddingX(1).italic().fg(.Green);

    var hBox = ui.Text.fromConstText(heightText);
    _ = hBox.styles.border(.Square).paddingX(1).bold().fg(.Blue);

    var aBox = ui.Text.fromConstText(areaText);
    _ = aBox.styles.border(.Rounded).paddingX(1).underline().fg(.Red);

    const topRow = try ui.Layout.fromElements(
        allocator,
        &[_]ui.UIElement{ wBox, hBox, aBox },
        // if (terminal.size.width % 2 == 0) .Vertical else .Horizontal,
        .Vertical,
    );

    var block = ui.Text.fromConstText("line one\nline two is longer\nthird");
    _ = block.styles.border(.Square).padding(1).bold().bg(.Blue);

    const plain = ui.Text.fromConstText("plain text, no styles");

    var styledLine = ui.Text.fromConstText("bold+italic+underline");
    _ = styledLine.styles.bold().italic().underline();

    const bottomRow = try ui.Layout.fromElements(
        allocator,
        &[_]ui.UIElement{ plain, styledLine },
        // if (terminal.size.width % 2 == 0) .Vertical else .Horizontal,
        .Vertical,
    );

    return try ui.Layout.fromElements(
        allocator,
        &[_]ui.UIElement{ topRow, block, bottomRow },
        // if (terminal.size.width % 2 == 0) .Horizontal else .Vertical,
        .Horizontal,
    );
}

pub const mockConfig: config.Config = .{
    .fullscreen = false,
};
