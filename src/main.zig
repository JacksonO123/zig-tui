const std = @import("std");
const Allocator = std.mem.Allocator;

const tui = @import("zig_tui");

const config: tui.Config = .{};

const IdPressedEvent = struct { []const u8 };

const customEvents: []const tui.events.EventDescription = &.{
    .{ .name = "id-pressed", .args = IdPressedEvent },
};

const EventDescription = tui.formatRegisteredEvents(tui.baseEvents ++ customEvents);

pub const Model = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        _ = self;
        _ = gpa;
    }
};

pub fn main(init: std.process.Init) !void {
    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdoutBuf);
    const writer = &stdout.interface;

    var model = Model.init();
    var context = try tui.initTuiLib(Model, init.gpa, init.io, config, &model, writer, customEvents);
    defer {
        model.deinit(init.gpa);
        context.deinit(writer);
        init.gpa.destroy(context);
    }

    try context.on("stdin", .{context}, stdinHandler);

    try context.render(init.io, renderUI, writer);
}

fn testCellFn(col: u16, row: u16, width: u16, height: u16) ?tui.SimpleDataStyle {
    const black = tui.RgbColor{ .r = 0, .g = 0, .b = 0 };
    const red = tui.RgbColor{ .r = 255, .g = 0, .b = 0 };
    const yellow = tui.RgbColor{ .r = 255, .g = 255, .b = 0 };
    const green = tui.RgbColor{ .r = 0, .g = 255, .b = 0 };

    const t: f64 = if (width > 1) @as(f64, @floatFromInt(col)) / @as(f64, @floatFromInt(width - 1)) else 0.0;
    const v: f64 = if (height > 1) @as(f64, @floatFromInt(row)) / @as(f64, @floatFromInt(height - 1)) else 0.0;

    const top = black.lerp(red, t);
    const bottom = green.lerp(yellow, t);
    const result = top.lerp(bottom, v);

    return .{
        .bg = .{ .Custom = result },
    };
}

fn renderUI(terminal: *tui.Terminal(Model, EventDescription)) !*tui.UIElement {
    const allocator = terminal.renderAlloc;

    var square = try tui.Text.fromConstText(allocator, "    ");
    _ = square.styles.border(.Rounded);

    var square2 = try tui.Text.fromConstText(allocator, "    ");
    _ = square2.styles.border(.Rounded);

    var text = try tui.Text.fromConstText(allocator, "    ");
    _ = text.styles.border(.Rounded);

    var text2 = try tui.Text.fromConstText(allocator, "    ");
    _ = text2.styles.border(.Rounded);

    var layout1 = try tui.Layout.builder(allocator, .Vertical)
        .elements(&.{ text2, text })
        .alignment(.End)
        .spacing(.Between)
        .build();
    _ = layout1.styles.border(.Rounded).cellFn(&testCellFn);

    const layout2 = try tui.Layout.builder(allocator, .Horizontal)
        .elements(&.{layout1})
        .constraints(&.{
            .{
                .width = .{ .Value = 40 },
                .height = .{ .Value = 16 },
            },
        })
        .build();

    const layout3 = try tui.Layout.builder(allocator, .Horizontal)
        .elements(&.{ square, layout2 })
        .build();

    const layout4 = try tui.Layout.builder(allocator, .Vertical)
        .elements(&.{ square2, layout3 })
        .build();

    return layout4;
}

fn stdinHandler(context: *tui.RenderContext(Model, EventDescription), data: []const u8) !void {
    _ = data;
    const rowInQuestion = context.backBuffer.buffer.items[1].items;
    for (rowInQuestion, 0..) |item, index| {
        if (item.style.bg == .Custom) {
            try context.logger.logBufPrint(1024, "({d}): {any}", .{ index, item.style.bg.Custom });
        }
    }
}
