const std = @import("std");
const Writer = std.Io.Writer;
const Allocator = std.mem.Allocator;
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

pub fn compatibleInitTuiLib(compatibleConfig: configMod.CompatibleConfig) !context.RenderContext {
    const config = configMod.Config{
        .rightPadding = compatibleConfig.rightPadding,
        .screenType = compatibleConfig.screenType,
    };
    const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const gpa: std.heap.DebugAllocator(.{}) = .init;
    const threaded: std.Io.Threaded = .init(gpa, .{});
    const io = threaded.io();
    return initTuiLib(gpa, arena.allocator(), io, config);
}

pub fn initTuiLib(
    gpa: Allocator,
    arenaAlloc: Allocator,
    io: std.Io,
    config: configMod.Config,
) !context.RenderContext {
    var globalArena = std.heap.ArenaAllocator.init(arenaAlloc);
    defer globalArena.deinit();
    const globalArenaAllocator = globalArena.allocator();

    var stdoutBuf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdoutBuf);
    const writer = &stdout.interface;

    var model = app.Model.init();
    var renderContext = try context.RenderContext.init(
        gpa,
        globalArenaAllocator,
        io,
        config,
        &model,
        writer,
    );
    defer renderContext.deinit(gpa, config, writer);
    errdefer renderContext.deinit(gpa, config, writer);

    while (true) {
        const timeoutMs: i32 = if (context.globalState.needsRerender) 1 else -1;
        const pollData, const readData = try renderContext.terminalInfo.pollEvents(timeoutMs);

        const neededRerender = context.globalState.needsRerender;
        context.globalState.needsRerender = false;

        if (pollData.includes(.Resize)) {
            const size = try utils.getTermSize(config);
            renderContext.onTerminalResize(size);
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
