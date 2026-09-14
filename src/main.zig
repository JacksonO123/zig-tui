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

    text: std.ArrayList(u8) = .empty,

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        self.text.deinit(gpa);
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

    try context.on("stdin", .{context.terminal}, stdinHandler);

    try context.render(init.io, renderUI, writer);
}

fn renderUI(terminal: *tui.Terminal(Model, EventDescription)) !*tui.UIElement {
    const allocator = terminal.renderAlloc;

    var input = try tui.Input.builder(allocator, terminal)
        .id("test-id")
        .focused(true)
        .placeholder("Type something")
        .value(terminal.model.text.items)
        .build();
    _ = input.styles.border(.Rounded);

    return input;
}

fn stdinHandler(terminal: *tui.Terminal(Model, EventDescription), data: []const u8) !void {
    if (data.len == 1 and data[0] == tui.keys.Backspace) {
        _ = terminal.model.text.pop();
    } else {
        try terminal.model.text.appendSlice(terminal.gpa, data);
    }
    terminal.stateChanged();
}
