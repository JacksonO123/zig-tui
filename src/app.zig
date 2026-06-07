const std = @import("std");
const Writer = std.Io.Writer;

const config = @import("config.zig");
const sequences = @import("sequences.zig");
const styles = @import("styles.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn renderUI(terminal: *terminalMod.Terminal) !*ui.UIElement {
    const allocator = terminal.allocator;
    const area: u32 = @as(u32, terminal.size.width) * @as(u32, terminal.size.height);

    const widthText = try std.fmt.allocPrint(allocator, "w: {d}", .{terminal.size.width});
    const heightText = try std.fmt.allocPrint(allocator, "h: {d}", .{terminal.size.height});
    const areaText = try std.fmt.allocPrint(allocator, "area: {d}", .{area});

    var wBox = try ui.Text.fromConstText(allocator, widthText);
    _ = wBox.styles.border(.Rounded).paddingX(1).italic().fg(.Green);

    var hBox = try ui.Text.fromConstText(allocator, heightText);
    _ = hBox.styles.border(.Square).paddingX(1).bold().fg(.Blue);

    var aBox = try ui.Text.fromConstText(allocator, areaText);
    _ = aBox.styles.border(.Rounded).paddingX(1).underline().fg(.Black).bg(.Red);

    const topRow = try ui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ wBox, hBox, aBox },
        &.{
            .{
                .width = .{ .Min = 25 },
            },
        },
        .Horizontal,
    );

    return topRow;

    // var block = try ui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    // _ = block.styles.padding(1).bold().bg(.Blue).border(.Square);

    // const plain = try ui.Text.fromConstText(allocator, "plain text, no styles");

    // var styledLine = try ui.Text.fromConstText(allocator, "bold+italic+underline");
    // _ = styledLine.styles.bold().italic().underline();

    // const bottomRow = try ui.Layout.fromElements(
    //     allocator,
    //     &.{ plain, styledLine },
    //     .Vertical,
    // );

    // return try ui.Layout.fromElements(
    //     allocator,
    //     &.{ topRow, block, bottomRow },
    //     .Horizontal,
    // );
}

pub const mockConfig: config.Config = .{
    .fullscreen = false,
};
