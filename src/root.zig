const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const c = @import("c");

const configMod = @import("config.zig");
const contextMod = @import("context.zig");
const renderer = @import("renderer.zig");
const sequences = @import("sequences.zig");
const termMod = @import("terminal.zig");
const utils = @import("utils.zig");
const ui = @import("ui.zig");

pub const Config = configMod.Config;
pub const Terminal = termMod.Terminal;
pub const UIElement = ui.UIElement;
pub const Text = ui.Text;
pub const Layout = ui.Layout;

pub inline fn initTuiLib(
    comptime ModelType: type,
    gpa: Allocator,
    io: std.Io,
    config: configMod.Config,
    model: *ModelType,
    writer: *Writer,
) !*contextMod.RenderContext(ModelType) {
    const ptr = try gpa.create(contextMod.RenderContext(ModelType));
    ptr.* = try contextMod.RenderContext(ModelType).init(
        gpa,
        io,
        config,
        model,
        writer,
    );
    return ptr;
}

pub fn render(
    comptime ModelType: type,
    context: *contextMod.RenderContext(ModelType),
    renderUI: renderer.RenderUIFn(ModelType),
    writer: *Writer,
) !void {
    while (true) {
        const timeoutMs: i32 = if (contextMod.globalState.needsRerender) 1 else -1;
        const pollData, const readData = try context.terminalInfo.pollEvents(timeoutMs);

        const neededRerender = contextMod.globalState.needsRerender;
        contextMod.globalState.needsRerender = false;

        if (pollData.includes(.Resize)) {
            const size = try utils.getTermSize(context.config);
            context.onTerminalResize(size);
            try renderer.handleRender(ModelType, context.gpa, context, renderUI, writer);
        }

        if (pollData.includes(.StateChange) or neededRerender) {
            try renderer.handleRender(ModelType, context.gpa, context, renderUI, writer);
        }

        if (pollData.includes(.Stdin)) {
            if (readData.len == 0) continue;
            for (readData) |byte| {
                switch (byte) {
                    'q', 0x03 => return,
                    else => {},
                }
            }
        }
    }
}
