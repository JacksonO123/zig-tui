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
const utils = @import("utils.zig");
const types = @import("types.zig");

// exports

// core
pub const Config = configMod.Config;
pub const RenderContext = contextMod.RenderContext;
pub const Terminal = termMod.Terminal;
pub const UIElement = ui.UIElement;

// events
pub const events = @import("events/event_exports.zig");
pub const keys = constants.keys;

// utils
pub const RgbColor = styles.RgbColor;
pub const Pos = utils.Pos;
pub const formatRegisteredEvents = eventListeners.formatRegisteredEvents;

// ui
pub const ElementLayoutInfo = ui.ElementLayoutInfo;
pub const Text = components.Text;
pub const Layout = components.Layout;
pub const Input = components.Input;
pub const Button = components.Button;
pub const getIdsContainingPoint = ui.getIdsContainingPoint;

const globalState = &@import("global.zig").globalState;

pub const baseEvents: []const eventListeners.EventDescription = &.{
    .{ .name = "stdin", .args = eventTypes.StdinEvent },
    .{ .name = "scroll", .args = eventTypes.ScrollEventWrapper },
    .{ .name = "mouse-btn", .args = eventTypes.MouseButtonEventWrapper },
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
