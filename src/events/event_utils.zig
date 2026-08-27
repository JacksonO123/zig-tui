const std = @import("std");

const eventTypes = @import("event_types.zig");

pub fn handleMouseEvent(stdinData: []const u8) ?struct { event: eventTypes.MouseEvent, len: usize } {
    if (!std.mem.startsWith(u8, stdinData, "\x1b[<")) return null;
    const end = std.mem.indexOfAny(u8, stdinData, "Mm") orelse return null;
    const data = stdinData[3..end];

    var it = std.mem.splitScalar(u8, data, ';');
    const cbStr = it.next() orelse return null;
    const cxStr = it.next() orelse return null;
    const cyStr = it.next() orelse return null;

    const cb = std.fmt.parseInt(u8, cbStr, 10) catch return null;
    const cx = std.fmt.parseInt(u16, cxStr, 10) catch return null;
    const cy = std.fmt.parseInt(u16, cyStr, 10) catch return null;

    return .{
        .event = .{
            .button = cb,
            .x = cx,
            .y = cy,
            .pressed = stdinData[end] == 'M',
        },
        .len = end + 1,
    };
}
