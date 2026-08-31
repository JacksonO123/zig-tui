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

    leftMouseDownIds: std.ArrayList([]const u8) = .empty,
    leftMouseUpIds: std.ArrayList([]const u8) = .empty,
    leftMousePressedIds: std.ArrayList([]const u8) = .empty,

    timeClicked: i64 = 0,
    barDuration: u64,

    pub fn init(barDuration: u64) Self {
        return .{ .barDuration = barDuration };
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        self.leftMouseDownIds.deinit(gpa);
        self.leftMouseUpIds.deinit(gpa);
        self.leftMousePressedIds.deinit(gpa);
    }
};

pub fn main(init: std.process.Init) !void {
    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdoutBuf);
    const writer = &stdout.interface;

    var model = Model.init(2500);
    var context = try tui.initTuiLib(Model, init.gpa, init.io, config, &model, writer, customEvents);
    defer {
        model.deinit(init.gpa);
        context.deinit(writer);
        init.gpa.destroy(context);
    }

    try context.on("click", .{context}, clickHandler);
    try context.on("id-pressed", .{context.terminal}, idPressedHandler);

    try context.render(init.io, renderUI, writer);
}

fn renderUI(terminal: *tui.Terminal(Model, EventDescription)) !*tui.UIElement {
    const allocator = terminal.renderAlloc;

    const now = std.Io.Timestamp.now(terminal.io, .awake).toMilliseconds();
    const diff: u64 = @max(0, now - terminal.model.timeClicked);
    const percent = @min(@as(f64, @floatFromInt(diff)) / @as(f64, @floatFromInt(terminal.model.barDuration)), 1);

    if (percent < 1) {
        terminal.stateChanged();
    }

    const bar = try progressBar(allocator, percent);

    var btn = try tui.Button.create(allocator, "show-btn", "Show");
    _ = btn.styles.border(.Rounded).bg(.Magenta).paddingX(4);

    const shownText = if (tui.stringArrContains(terminal.model.leftMousePressedIds.items, "show-btn"))
        try tui.Text.fromConstText(allocator, "i am shown")
    else
        null;

    const hLayout = try tui.Layout.fromElements(
        allocator,
        &.{ btn, shownText },
        .Horizontal,
    );

    const layout = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ bar, hLayout },
        &.{.{ .width = .Fill }},
        .Vertical,
    );

    return layout;
}

fn progressBar(allocator: Allocator, percent: f64) !*tui.UIElement {
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

fn clickHandler(
    context: *tui.RenderContext(Model, EventDescription),
    data: tui.events.MouseButtonEvent,
) !void {
    switch (data.button) {
        .Left => a: {
            if (data.pressed) {
                context.model.leftMouseDownIds.clearRetainingCapacity();
                context.model.leftMousePressedIds.clearRetainingCapacity();

                const rendered = context.rendered orelse break :a;
                try tui.getIdsContainingPoint(
                    context.gpa,
                    rendered,
                    data.toPos(),
                    &context.model.leftMouseDownIds,
                );
            } else {
                context.model.leftMouseUpIds.clearRetainingCapacity();
                context.model.leftMousePressedIds.clearRetainingCapacity();

                const rendered = context.rendered orelse break :a;
                try tui.getIdsContainingPoint(
                    context.gpa,
                    rendered,
                    data.toPos(),
                    &context.model.leftMouseUpIds,
                );

                for (context.model.leftMouseUpIds.items) |upId| {
                    if (tui.stringArrContains(context.model.leftMouseDownIds.items, upId)) {
                        try context.model.leftMousePressedIds.append(context.gpa, upId);
                    }
                }
            }

            context.terminal.stateChanged();
        },
        else => {},
    }

    for (context.model.leftMousePressedIds.items) |id| {
        try context.emit("id-pressed", .{id});
    }
}

fn idPressedHandler(terminal: *tui.Terminal(Model, EventDescription), id: []const u8) !void {
    try terminal.logger.logBufPrint(2048, "{any}", .{id});
    if (std.mem.eql(u8, id, "show-btn")) {
        terminal.model.timeClicked = std.Io.Timestamp.now(terminal.io, .awake).toMilliseconds();
    }
}
