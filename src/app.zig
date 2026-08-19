const std = @import("std");
const Writer = std.Io.Writer;

const configMod = @import("config.zig");
const sequences = @import("sequences.zig");
const styles = @import("styles.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub const config: configMod.Config = .{
    .screenType = .Alternate,
};

pub const Model = struct {
    const Self = @This();

    count: usize = 0,
    toRender: usize = 0,

    pub fn init() Self {
        return .{};
    }
};

pub fn renderUI(terminal: *terminalMod.Terminal) !*ui.UIElement {
    const allocator = terminal.renderAlloc;
    defer {
        terminal.model.count += 1;

        if (terminal.model.count % 100 == 0) {
            terminal.model.toRender = terminal.model.count;
        }

        terminalMod.Terminal.stateChanged();
    }

    var block = try ui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    _ = block.styles.padding(1).bold().bg(.Blue).border(.Square);

    var block2 = try ui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    _ = block2.styles.padding(1).bold().bg(.Red).border(.Square);

    var block3 = try ui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    _ = block3.styles.padding(1).bold().bg(.Green).border(.Square);

    const fmtString = try std.fmt.allocPrint(
        terminal.renderAlloc,
        "plain text, no styles: {d}.",
        .{terminal.model.toRender},
    );
    const plain = try ui.Text.fromConstText(allocator, fmtString);

    const layout = try ui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ block, block2, plain },
        &.{.{
            .width = .{ .Fill = {} },
        }},
        .Horizontal,
    );
    _ = layout.styles.gap(2);

    const layout2 = try ui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ layout, block3 },
        &.{
            .{},
            .{
                .height = .{ .Fill = {} },
                .width = .{ .Fill = {} },
            },
        },
        .Vertical,
    );
    _ = layout2.styles.gap(1);

    return layout2;
}
