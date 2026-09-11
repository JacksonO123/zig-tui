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

    try context.on("scroll", .{context.terminal}, scrollHandler);

    try context.render(init.io, renderUI, writer);
}

fn renderUI(terminal: *tui.Terminal(Model, EventDescription)) !*tui.UIElement {
    const allocator = terminal.renderAlloc;

    const amount = 60;
    var elements: std.ArrayList(*tui.UIElement) = .empty;

    var i: usize = 0;
    while (i < amount) : (i += 1) {
        const buf = try allocator.alloc(u8, i + 1);
        @memset(buf, 'a');
        const text = try tui.Text.fromConstText(allocator, buf);
        const text2 = try text.clone(allocator);
        try elements.append(allocator, text);
        try elements.append(allocator, text2);
    }

    const layout = try tui.Layout.builder(allocator, .Vertical).elements(elements.items).build();
    return layout;
}

fn scrollHandler(terminal: *tui.Terminal(Model, EventDescription), data: tui.events.ScrollEvent) !void {
    switch (data.direction) {
        .Up => terminal.scrollOffset += 1,
        .Down => terminal.scrollOffset -|= 1,
    }
    terminal.stateChanged();
}
