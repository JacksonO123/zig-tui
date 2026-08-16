const std = @import("std");
const Writer = std.Io.Writer;

const config = @import("config.zig");
const sequences = @import("sequences.zig");
const styles = @import("styles.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub fn renderUI(terminal: *terminalMod.Terminal) !*ui.UIElement {
    const allocator = terminal.renderAlloc;

    // var someText = try ui.Text.fromConstText(allocator, "some lo\nng tex\nt that\n is lon\nger th\nan 10\n ch\nars");
    // _ = someText.styles.border(.Square);

    // var hText = try ui.Text.fromConstText(allocator, "h");
    // _ = hText.styles.border(.Rounded).fg(.Blue);

    // const layout = try ui.Layout.fromElementsAndConstraints(
    //     allocator,
    //     &.{ someText, hText },
    //     &.{
    //         .{
    //             .width = .{ .Max = 10 },
    //             .height = .{ .Max = 4 },
    //         },
    //     },
    //     .Horizontal,
    // );

    var block = try ui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    _ = block.styles.padding(1).bold().bg(.Blue).border(.Square);

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
    //     &.{ layout, block, bottomRow },
    //     .Horizontal,
    // );

    return try ui.Layout.fromElementsAndConstraints(
        allocator,
        &.{block},
        &.{.{
            .width = .{
                .Ratio = .{ .numerator = 3, .denominator = 4 },
            },
        }},
        .Horizontal,
    );
}

pub const mockConfig: config.Config = .{};
