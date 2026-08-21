const std = @import("std");
const tui = @import("zig_tui");

const config: tui.Config = .{
    .screenType = .Alternate,
};

pub const Model = struct {
    const Self = @This();

    count: usize = 0,
    toRender: usize = 0,

    pub fn init() Self {
        return .{};
    }
};

pub fn renderUI(terminal: *tui.Terminal(Model)) !*tui.UIElement {
    const allocator = terminal.renderAlloc;
    defer {
        terminal.model.count += 1;

        if (terminal.model.count % 100 == 0) {
            terminal.model.toRender = terminal.model.count;
        }

        terminal.stateChanged();
    }

    var block = try tui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    _ = block.styles.padding(1).bold().bg(.Blue).border(.Square);

    var block2 = try tui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    _ = block2.styles.padding(1).bold().bg(.Red).border(.Square);

    var block3 = try tui.Text.fromConstText(allocator, "line one\nline two is longer\nthird");
    _ = block3.styles.padding(1).bold().bg(.Green).border(.Square);

    const fmtString = try std.fmt.allocPrint(
        terminal.renderAlloc,
        "plain text, no styles: {d}.",
        .{terminal.model.toRender},
    );
    const plain = try tui.Text.fromConstText(allocator, fmtString);

    const layout = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ block, block2, plain },
        &.{.{
            .width = .{ .Fill = {} },
        }},
        .Horizontal,
    );
    _ = layout.styles.gap(2);

    const layout2 = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ layout, block3 },
        &.{
            .{},
            .{
                .height = .{ .Fill = {} },
                .width = .{ .Fill = {} },
            },
        },
        .Vertical,
    );
    _ = layout2.styles.gap(1);

    return layout2;
}

const Test = struct { u32 };

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
    errdefer {
        context.deinit(writer);
        init.gpa.destroy(context);
    }

    try context.onEvent("stdin", somethingHandler, .{context}, tui.events.StdinEvent);

    try tui.render(Model, context, renderUI, writer);
}

fn somethingHandler(
    contextArgs: struct { *tui.RenderContext(Model) },
    args: tui.events.StdinEvent,
) void {
    contextArgs[0].logger.logBufPrint(16, "{s}", .{args.data}) catch {};
}
