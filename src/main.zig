const std = @import("std");
const Allocator = std.mem.Allocator;

const tui = @import("zig_tui");

const config: tui.Config = .{
    .screenType = .Alternate,
};

pub const Model = struct {
    const Self = @This();

    count: usize = 0,
    toRender: usize = 0,
    string: []const u8 = &.{},

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self, gpa: Allocator) void {
        gpa.free(self.string);
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

    const fmtString1 = try std.fmt.allocPrint(
        terminal.renderAlloc,
        "line one\nline two is longer\n{s}",
        .{terminal.model.string},
    );
    var block3 = try tui.Text.fromConstText(allocator, fmtString1);
    _ = block3.styles.padding(1).bold().bg(.Green).border(.Square);

    const fmtString2 = try std.fmt.allocPrint(
        terminal.renderAlloc,
        "plain text, no styles: {d}.",
        .{terminal.model.toRender},
    );
    const plain = try tui.Text.fromConstText(allocator, fmtString2);

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
    defer model.deinit(context.terminal.gpa);

    try context.on("stdin", .{context.terminal}, stdinHandler);

    try tui.render(Model, context, renderUI, writer);
}

fn stdinHandler(terminal: *tui.Terminal(Model), data: []const u8) void {
    terminal.logger.logBufPrint(16, "{s}", .{data}) catch {};

    const newString = std.fmt.allocPrint(
        terminal.gpa,
        "{s}{s}",
        .{ terminal.model.string, data },
    ) catch "";
    terminal.gpa.free(terminal.model.string);
    terminal.model.string = newString;
    terminal.stateChanged();
}
