const std = @import("std");
const Allocator = std.mem.Allocator;

const tui = @import("zig_tui");

const config: tui.Config = .{};

pub const Model = struct {
    const Self = @This();

    counter: u32 = 0,
    to: u32,

    inputValue: []const u8 = &.{},

    pub fn init(to: u32) Self {
        return .{ .to = to };
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.inputValue);
    }
};

fn progressBar(allocator: Allocator, percent: f32) !*tui.UIElement {
    const green = tui.RgbColor.from(0, 232, 93);
    const red = tui.RgbColor.from(214, 65, 60);
    const barColor = red.lerp(green, percent);

    var bar = try tui.Text.fromConstText(allocator, "");
    _ = bar.styles.bg(.{ .Custom = barColor });

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

    var input = try tui.Input.fromValueAndPlaceholder(
        allocator,
        "input",
        terminal.model.inputValue,
        "Enter some text",
        true,
    );
    _ = input.styles.border(.Rounded);

    const layout = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ text, bar, input },
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
        model.deinit(init.gpa);
        context.deinit(writer);
        init.gpa.destroy(context);
    }

    try context.on("stdin", .{context.terminal}, stdinHandler);

    try tui.render(Model, init.io, context, renderUI, writer);
}

fn stdinHandler(terminal: *tui.Terminal(Model), data: []const u8) !void {
    const newStr = if (data[0] == tui.keys.Backspace)
        try terminal.gpa.dupe(u8, terminal.model.inputValue[0..terminal.model.inputValue.len -| 1])
    else
        try std.fmt.allocPrint(terminal.gpa, "{s}{s}", .{ terminal.model.inputValue, data });

    terminal.gpa.free(terminal.model.inputValue);
    terminal.model.inputValue = newStr;

    terminal.stateChanged();
}
