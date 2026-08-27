const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;

const c = @import("c");

const components = @import("components.zig");
const configMod = @import("config.zig");
const constants = @import("constants.zig");
const contextMod = @import("context.zig");
const eventListeners = @import("events/event_listeners.zig");
const eventTypes = @import("events/event_types.zig");
const eventUtils = @import("events/event_utils.zig");
const renderer = @import("renderer.zig");
const styles = @import("styles.zig");
const terminalUtils = @import("terminal_utils.zig");
const termMod = @import("terminal.zig");
const ui = @import("ui.zig");

// exports
pub const events = @import("events/event_exports.zig");
pub const Text = components.Text;
pub const Layout = components.Layout;
pub const Config = configMod.Config;
pub const RenderContext = contextMod.RenderContext;
pub const Terminal = termMod.Terminal;
pub const UIElement = ui.UIElement;
pub const Input = components.Input;
pub const keys = constants.keys;
pub const RgbColor = styles.RgbColor;

const globalState = &@import("global.zig").globalState;

pub const baseEvents: []const eventListeners.EventDescription = &.{
    .{ .name = "stdin", .args = eventTypes.StdinEvent },
    .{ .name = "scroll", .args = eventTypes.ScrollEventWrapper },
    .{ .name = "mouse-btn", .args = eventTypes.MouseEventWrapper },
};

pub inline fn initTuiLib(
    comptime ModelType: type,
    gpa: Allocator,
    io: std.Io,
    config: configMod.Config,
    model: *ModelType,
    writer: *Writer,
) !*contextMod.RenderContext(ModelType, eventListeners.formatRegisteredEvents(baseEvents)) {
    const RenderContextType = contextMod.RenderContext(
        ModelType,
        eventListeners.formatRegisteredEvents(baseEvents),
    );
    const ptr = try gpa.create(RenderContextType);
    ptr.* = try RenderContextType.init(
        gpa,
        io,
        config,
        model,
        writer,
    );
    try contextMod.postInit(@ptrCast(ptr), writer);
    return ptr;
}

pub fn render(
    comptime ModelType: type,
    io: std.Io,
    context: *contextMod.RenderContext(
        ModelType,
        eventListeners.formatRegisteredEvents(baseEvents),
    ),
    renderUI: renderer.RenderUIFn(ModelType),
    writer: *Writer,
) !void {
    while (true) {
        var allow = true;
        defer {
            if (allow) {
                globalState.eventUtil.event.reset();
            }
        }

        const pollData, var readData = try context.terminalUtils.pollEvents(
            io,
            globalState.needsRerender,
        );
        const neededRerender = globalState.needsRerender;
        globalState.needsRerender = false;

        if (pollData.includes(.Resize)) {
            const size = try terminalUtils.getTermSize(context.config);
            context.terminalUtils.onTerminalResize(context.config, &context.state, size);
            try renderer.handleRender(ModelType, context.gpa, @ptrCast(context), renderUI, writer);
        }

        if (pollData.includes(.StateChange) or neededRerender) {
            try renderer.handleRender(ModelType, context.gpa, @ptrCast(context), renderUI, writer);
        }

        if (pollData.includes(.Stdin)) {
            allow = false;

            if (readData.len == 0) continue;

            while (readData.len > 0) {
                if (eventUtils.handleMouseEvent(readData)) |eventData| {
                    switch (eventData.event.button) {
                        64, 65 => {
                            const direction: eventTypes.ScrollDirection = switch (eventData.event.button) {
                                64 => .Up,
                                65 => .Down,
                                else => unreachable,
                            };
                            const scrollEvent = eventTypes.ScrollEvent{
                                .direction = direction,
                                .pos = .{
                                    .x = eventData.event.x,
                                    .y = eventData.event.y,
                                },
                            };
                            try context.emit("scroll", .{scrollEvent});
                        },
                        else => {
                            try context.emit("mouse-btn", .{eventData.event});
                        },
                    }

                    readData = readData[eventData.len..];
                }

                if (readData.len == 0) break;

                for (readData) |byte| {
                    switch (byte) {
                        // ctrl c
                        3,
                        // esc
                        27,
                        => return,
                        else => {},
                    }
                }

                try context.emit("stdin", .{readData});
                readData = &.{};
            }
        }
    }
}
