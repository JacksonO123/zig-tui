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
const utils = @import("utils.zig");
const termMod = @import("terminal.zig");

var resizePipeWriteFd: std.posix.fd_t = -1;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena;
    const globalArenaAllocator = arena.allocator();

    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdoutBuf);
    const writer = &stdout.interface;

    var renderContext = try context.RenderContext.init(
        gpa,
        globalArenaAllocator,
        app.mockConfig,
        writer,
    );
    defer renderContext.deinit(gpa, writer);
    errdefer renderContext.deinit(gpa, writer);

    var el = try app.renderUI(&renderContext.terminal);
    try renderer.render(gpa, &renderContext, el, writer);

    while (true) {
        const pollData, const readData = try renderContext.terminalInfo.pollEvents();

        if (pollData.includes(.Resize)) {
            const size = try termMod.TerminalInfo.getTermSize();
            try renderContext.onTerminalResize(size);
            renderContext.prepareForReRender();
            el = try app.renderUI(&renderContext.terminal);
            try renderer.render(gpa, &renderContext, el, writer);
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
