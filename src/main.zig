const std = @import("std");
const Allocator = std.mem.Allocator;

const tui = @import("zig_tui");

const config: tui.Config = .{};

pub const Model = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }
};

pub fn renderUI(terminal: *tui.Terminal(Model)) !*tui.UIElement {
    const allocator = terminal.renderAlloc;

    var text = try tui.Text.fromConstText(allocator, "this is a longer string than is able to be rendered in the box");
    _ = text.styles.border(.Rounded).wordWrap(true).bg(.Cyan).fg(.Black);

    const layout = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{text},
        &.{
            .{
                .width = .{
                    .Fill = {},
                },
            },
        },
        .Horizontal,
    );

    return layout;
}

pub fn main(init: std.process.Init) !void {
    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdoutBuf);
    const writer = &stdout.interface;

    var model = Model.init();
    var context = try tui.initTuiLib(Model, init.gpa, init.io, config, &model, writer);
    defer {
        context.deinit(writer);
        init.gpa.destroy(context);
    }

    try context.on("scroll", .{context.terminal}, scrollHandler);
    try context.on("mouse-btn", .{context.terminal}, mouseBtnHandler);

    try tui.render(Model, init.io, context, renderUI, writer);
}

fn scrollHandler(terminal: *tui.Terminal(Model), event: tui.events.ScrollEvent) void {
    terminal.logger.logBufPrint(2048, "{any}", .{event}) catch {};
}

fn mouseBtnHandler(terminal: *tui.Terminal(Model), event: tui.events.MouseEvent) void {
    terminal.logger.logBufPrint(2048, "{any}", .{event}) catch {};
}
