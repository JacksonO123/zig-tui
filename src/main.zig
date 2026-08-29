const std = @import("std");
const Allocator = std.mem.Allocator;

const tui = @import("zig_tui");

const config: tui.Config = .{};

pub const Model = struct {
    const Self = @This();

    hidden: bool = false,
    counter: u32 = 0,
    to: u32,

    inputValue: []const u8 = &.{},

    leftMouseDownIds: ?[]const []const u8 = null,
    mouseUpId: ?[]const u8 = null,

    pub fn init(to: u32) Self {
        return .{ .to = to };
    }

    pub fn deinit(self: Self, allocator: Allocator) void {
        allocator.free(self.inputValue);
        if (self.leftMouseDownIds) |ids| {
            allocator.free(ids);
        }
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
        &.{.{
            .width = .{
                .Percent = percent,
            },
        }},
        .Horizontal,
    );
    _ = layout.styles.border(.Rounded);

    return layout;
}

fn renderUI(terminal: *tui.Terminal(Model, tui.formatRegisteredEvents(tui.baseEvents))) !*tui.UIElement {
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

    const input = if (!terminal.model.hidden) a: {
        var input = try tui.Input.fromValueAndPlaceholder(
            allocator,
            "input",
            terminal.model.inputValue,
            "Enter some text",
            true,
        );
        _ = input.styles.border(.Rounded);
        break :a input;
    } else null;

    var button = try tui.Button.create(allocator, "button", "Click me");
    _ = button.styles.border(.Rounded).bg(.Magenta).fg(.Black);

    var textsList: std.ArrayList(*tui.UIElement) = .empty;
    if (terminal.model.leftMouseDownIds) |ids| {
        for (ids) |id| {
            const idText = try tui.Text.fromConstText(allocator, id);
            try textsList.append(allocator, idText);
        }
    }

    const textsLayout = try tui.Layout.fromElements(allocator, textsList.items, .Horizontal);

    const hiImHere = if (terminal.model.leftMouseDownIds) |ids|
        if (containsSlice(ids, "button"))
            try tui.Text.fromConstText(allocator, "hi im here")
        else
            null
    else
        null;

    const hLayout = try tui.Layout.fromElements(allocator, &.{ input, button, hiImHere }, .Horizontal);

    const layout = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ text, bar, hLayout, textsLayout },
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

fn containsSlice(haystack: []const []const u8, value: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, value)) return true;
    }

    return false;
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
    try context.on("mouse-btn", .{context}, mouseHandler);

    try context.render(init.io, renderUI, writer);
}

fn stdinHandler(
    terminal: *tui.Terminal(Model, tui.formatRegisteredEvents(tui.baseEvents)),
    data: []const u8,
) !void {
    const newStr = if (data[0] == tui.keys.Backspace)
        try terminal.gpa.dupe(u8, terminal.model.inputValue[0..terminal.model.inputValue.len -| 1])
    else
        try std.fmt.allocPrint(terminal.gpa, "{s}{s}", .{ terminal.model.inputValue, data });

    terminal.gpa.free(terminal.model.inputValue);
    terminal.model.inputValue = newStr;

    terminal.stateChanged();
}

fn mouseHandler(
    context: *tui.RenderContext(Model, tui.formatRegisteredEvents(tui.baseEvents)),
    data: tui.events.MouseButtonEvent,
) !void {
    switch (data.button) {
        .Left => a: {
            if (data.pressed) {
                const point = tui.Pos{ .x = data.x, .y = data.y };
                var ids: std.ArrayList([]const u8) = .empty;
                const rendered = context.rendered orelse break :a;
                try tui.getIdsContainingPoint(context.gpa, rendered, point, &ids);

                if (context.model.leftMouseDownIds) |*modelIds| {
                    context.gpa.free(modelIds.*);
                    modelIds.* = try ids.toOwnedSlice(context.gpa);
                } else {
                    context.model.leftMouseDownIds = try ids.toOwnedSlice(context.gpa);
                }
            } else {
                const ids = context.model.leftMouseDownIds orelse break :a;
                context.gpa.free(ids);
                context.model.leftMouseDownIds = null;
            }

            context.terminal.stateChanged();
        },
        else => {},
    }
}
