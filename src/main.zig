const std = @import("std");
const Allocator = std.mem.Allocator;

const tui = @import("zig_tui");

const config: tui.Config = .{};

pub const Model = struct {
    const Self = @This();

    leftMouseDownIds: std.ArrayList([]const u8) = .empty,
    leftMouseUpIds: std.ArrayList([]const u8) = .empty,
    leftMousePressedIds: std.ArrayList([]const u8) = .empty,

    pub fn init() Self {
        return .{};
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

    var model = Model.init();
    var context = try tui.initTuiLib(Model, init.gpa, init.io, config, &model, writer);
    defer {
        model.deinit(init.gpa);
        context.deinit(writer);
        init.gpa.destroy(context);
    }

    try context.on("click", .{context}, clickHandler);

    try context.render(init.io, renderUI, writer);
}

fn renderUI(terminal: *tui.Terminal(Model, tui.formatRegisteredEvents(tui.baseEvents))) !*tui.UIElement {
    const allocator = terminal.renderAlloc;

    var btn = try tui.Button.create(allocator, "show-btn", "Show");
    _ = btn.styles.border(.Rounded).bg(.Magenta).paddingX(4);

    const shownText = if (tui.stringArrContains(terminal.model.leftMousePressedIds.items, "show-btn"))
        try tui.Text.fromConstText(allocator, "i am shown")
    else
        null;

    const layout = try tui.Layout.fromElements(
        allocator,
        &.{ btn, shownText },
        .Horizontal,
    );

    return layout;
}

fn clickHandler(
    context: *tui.RenderContext(Model, tui.formatRegisteredEvents(tui.baseEvents)),
    data: tui.events.MouseButtonEvent,
) !void {
    switch (data.button) {
        .Left => a: {
            if (data.pressed) {
                context.model.leftMouseDownIds.clearRetainingCapacity();

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
}
