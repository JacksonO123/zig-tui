const std = @import("std");
const Writer = std.Io.Writer;
const builtin = @import("builtin");

const c = @import("c");
const zig_tui = @import("zig_tui");

const app = @import("app.zig");
const configMod = @import("config.zig");
const context = @import("context.zig");
const renderer = @import("renderer.zig");
const sequences = @import("sequences.zig");
const termMod = @import("terminal.zig");
const utils = @import("utils.zig");

var resizePipeWriteFd: std.posix.fd_t = -1;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena;
    const globalArenaAllocator = arena.allocator();

    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdoutBuf);
    const writer = &stdout.interface;

    var model = app.Model.init();
    var renderContext = try context.RenderContext.init(
        gpa,
        globalArenaAllocator,
        io,
        app.config,
        &model,
        writer,
    );
    defer renderContext.deinit(gpa, app.config, writer);
    errdefer renderContext.deinit(gpa, app.config, writer);

    while (true) {
        const timeoutMs: i32 = if (context.globalState.needsRerender) 1 else -1;
        const pollData, const readData = try renderContext.terminalInfo.pollEvents(timeoutMs);

        const neededRerender = context.globalState.needsRerender;
        context.globalState.needsRerender = false;

        if (pollData.includes(.Resize)) {
            const size = try utils.getTermSize(app.config);
            renderContext.onTerminalResize(size);

            try sequences.requestCursorPosition(writer);
            try writer.flush();
            const row = try utils.readCursorPositionReport();
            renderContext.state.rowOffset = row;

            try renderer.handleRender(gpa, &renderContext, writer);
        }

        if (pollData.includes(.StateChange) or neededRerender) {
            try renderer.handleRender(gpa, &renderContext, writer);
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
