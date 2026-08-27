const std = @import("std");
const Allocator = std.mem.Allocator;

const tui = @import("zig_tui");

const config: tui.Config = .{};

pub const Model = struct {
    const Self = @This();

    counter: u32 = 0,
    to: u32,

    pub fn init(to: u32) Self {
        return .{ .to = to };
    }
};

fn progressBar(allocator: Allocator, percent: f32) !*tui.UIElement {
    var bar = try tui.Text.fromConstText(allocator, "");
    _ = bar.styles.bg(if (percent < 0.33) .Red else if (percent < 0.66) .Yellow else .Green);

    var layout = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{bar},
        &.{
            .{
                .width = .{
                    .Percent = percent,
                },
            },
        },
        .Horizontal,
    );
    _ = layout.styles.border(.Rounded);

    return layout;
}

fn renderUI(terminal: *tui.Terminal(Model)) !*tui.UIElement {
    if (terminal.model.counter < terminal.model.to) {
        terminal.model.counter += 1;
        terminal.stateChanged();
    }

    const allocator = terminal.renderAlloc;

    const percent: f32 = a: {
        const floatCounter: f32 = @floatFromInt(terminal.model.counter);
        const floatTo: f32 = @floatFromInt(terminal.model.to);
        const res = floatCounter / floatTo;
        break :a @min(1, res);
    };

    const fmtString = try std.fmt.allocPrint(allocator, "- Progress: {d}% -", .{@floor(percent * 100)});
    const text = try tui.Text.fromConstText(allocator, fmtString);

    const bar = try progressBar(allocator, percent);

    const layout = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ text, bar },
        &.{
            .{},
            .{
                .width = .{
                    .Fill = {},
                },
            },
        },
        .Vertical,
    );

    return layout;
}

pub fn main(init: std.process.Init) !void {
    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdoutBuf);
    const writer = &stdout.interface;

    var model = Model.init(1000);
    var context = try tui.initTuiLib(Model, init.gpa, init.io, config, &model, writer);
    defer {
        context.deinit(writer);
        init.gpa.destroy(context);
    }

    try tui.render(Model, init.io, context, renderUI, writer);
}
