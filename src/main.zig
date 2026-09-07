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

fn aCellFn(x: u16, y: u16, width: u16, height: u16) ?tui.SimpleDataStyle {
    _ = width;
    _ = height;
    _ = y;
    const red = tui.RgbColor.from(255, 0, 0);

    _ = x;
    _ = red;
    return null;

    // if (x % 2 == 0) return .{
    //     .bg = .{ .Custom = red },
    // };

    // return .{ .bg = .Black };
}

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

fn renderUI(terminal: *tui.Terminal(Model, EventDescription)) !*tui.UIElement {
    const allocator = terminal.renderAlloc;

    var text = try tui.Text.fromConstText(allocator, "    ");
    _ = text.styles.border(.Rounded);

    var text2 = try tui.Text.fromConstText(allocator, "    ");
    _ = text2.styles.border(.Rounded);

    var layout1 = try tui.Layout.builder(allocator, .Horizontal)
        .elements(&.{ text2, text })
        .alignment(.End)
        // .spacing(.Between)
        .build();
    _ = layout1.styles.border(.Rounded).cellFn(aCellFn);

    const layout2 = try tui.Layout.builder(allocator, .Horizontal)
        .elements(&.{layout1})
        .constraints(&.{
            .{
                .width = .Fill,
            },
        })
        .build();

    return layout2;
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
