const std = @import("std");
const Allocator = std.mem.Allocator;

const tui = @import("zig_tui");

const config: tui.Config = .{};

pub const Model = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }
};

pub fn main(init: std.process.Init) !void {
    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdoutBuf);
    const writer = &stdout.interface;

    var model = Model.init();
    var context = try tui.initTuiLib(Model, init.gpa, init.io, config, &model, writer);
    defer {
        model.deinit();
        context.deinit(writer);
        init.gpa.destroy(context);
    }

    try context.render(init.io, renderUI, writer);
}

fn renderUI(terminal: *tui.Terminal(Model, tui.formatRegisteredEvents(tui.baseEvents))) !*tui.UIElement {
    const allocator = terminal.renderAlloc;

    var text1 = try tui.Text.fromConstText(allocator, "     ");
    _ = text1.styles.border(.Rounded);

    var text2 = try tui.Text.fromConstText(allocator, "     ");
    _ = text2.styles.border(.Rounded);

    var text3 = try tui.Text.fromConstText(allocator, "this is a string\non multiple lines\nthat is on multiple lines");
    _ = text3.styles.border(.Rounded).bg(.Blue);

    var absoluteText = try tui.Text.fromConstText(allocator, "absolute text");
    _ = absoluteText.styles.border(.Square).position(.{ .Absolute = .{ .x = 1, .y = 1 } });

    var hLayout = try tui.Layout.fromElements(allocator, &.{
        text3, absoluteText,
    }, .Vertical);
    _ = hLayout.styles.setRelativeAnchor(true);

    var afterText = try tui.Text.fromConstText(allocator, "     ");
    _ = afterText.styles.border(.Rounded);

    var layout = try tui.Layout.fromElementsAndConstraints(
        allocator,
        &.{ text1, text2, hLayout, afterText },
        &.{ .{}, .{ .height = .Fill } },
        .Vertical,
    );
    _ = layout.styles.gap(2);

    return layout;
}
