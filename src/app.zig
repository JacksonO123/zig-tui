const std = @import("std");
const Writer = std.Io.Writer;

const configMod = @import("config.zig");
const sequences = @import("sequences.zig");
const styles = @import("styles.zig");
const terminalMod = @import("terminal.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

pub const config: configMod.Config = .{};

pub const Model = struct {
    const Self = @This();

    count: usize,

    pub fn init() Self {
        return .{ .count = 0 };
    }
};

pub fn renderUI(terminal: *terminalMod.Terminal) !*ui.UIElement {
    const allocator = terminal.renderAlloc;
    defer {
        terminal.model.count += 1;
        terminalMod.Terminal.stateChanged();
    }

    var block = try ui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    _ = block.styles.padding(1).bold().bg(.Blue).border(.Square);

    const fmtString = try std.fmt.allocPrint(
        terminal.renderAlloc,
        "plain text, no styles: {d}",
        .{terminal.model.count},
    );
    const plain = try ui.Text.fromConstText(allocator, fmtString);

    const layout = try ui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ block, plain },
        &.{.{
            .width = .{ .Fill = {} },
        }},
        .Horizontal,
    );
    _ = layout.styles.gap(2);

    return layout;
}
