const std = @import("std");

const utils = @import("../utils.zig");

const globalMod = @import("../global.zig");

const windows = std.os.windows;
const UserIo = windows.CONSOLE.USER_IO;

const mode = struct {
    const PROCESSED_INPUT: windows.DWORD = 0x0001;
    const LINE_INPUT: windows.DWORD = 0x0002;
    const ECHO_INPUT: windows.DWORD = 0x0004;
    const MOUSE_INPUT: windows.DWORD = 0x0010;
    const QUICK_EDIT_MODE: windows.DWORD = 0x0040;
    const EXTENDED_FLAGS: windows.DWORD = 0x0080;
    const VIRTUAL_TERMINAL_INPUT: windows.DWORD = 0x0200;

    const PROCESSED_OUTPUT: windows.DWORD = 0x0001;
    const VIRTUAL_TERMINAL_PROCESSING: windows.DWORD = windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING;
};

const utf8_code_page: windows.UINT = 65001;

const resize_poll_interval_ms = 50;

const SavedState = struct {
    inputMode: windows.DWORD,
    outputMode: windows.DWORD,
    inputCodePage: windows.UINT,
    outputCodePage: windows.UINT,
};

var savedState: ?SavedState = null;

var resizeWatch: struct {
    thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = .init(false),
} = .{};

pub fn enterRawMode(io: std.Io) !void {
    const stdin = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();

    const original: SavedState = .{
        .inputMode = try getConsoleMode(io, stdin),
        .outputMode = try getConsoleMode(io, stdout),
        .inputCodePage = try getCodePage(io, .Input),
        .outputCodePage = try getCodePage(io, .Output),
    };
    savedState = original;

    const rawInput = (original.inputMode & ~(mode.PROCESSED_INPUT |
        mode.LINE_INPUT |
        mode.ECHO_INPUT |
        mode.QUICK_EDIT_MODE)) |
        mode.VIRTUAL_TERMINAL_INPUT |
        mode.MOUSE_INPUT |
        mode.EXTENDED_FLAGS;

    const rawOutput = original.outputMode |
        mode.PROCESSED_OUTPUT |
        mode.VIRTUAL_TERMINAL_PROCESSING;

    try setConsoleMode(io, stdin, rawInput);
    try setConsoleMode(io, stdout, rawOutput);

    try setCodePage(io, .Input, utf8_code_page);
    try setCodePage(io, .Output, utf8_code_page);
}

pub fn exitRawMode(io: std.Io) void {
    const original = savedState orelse return;

    setCodePage(io, .Output, original.outputCodePage) catch {};
    setCodePage(io, .Input, original.inputCodePage) catch {};
    setConsoleMode(io, std.Io.File.stdout(), original.outputMode) catch {};
    setConsoleMode(io, std.Io.File.stdin(), original.inputMode) catch {};

    savedState = null;
}

pub fn getTerminalSize(io: std.Io) !utils.Size {
    var op = UserIo.GET_SCREEN_BUFFER_INFO;
    switch (try op.operate(io, std.Io.File.stdout())) {
        .SUCCESS => {},
        else => return error.FailedToGetTerminalSize,
    }

    return .{
        .width = @intCast(@max(0, op.Data.dwWindowSize.X)),
        .height = @intCast(@max(0, op.Data.dwWindowSize.Y)),
    };
}

pub fn startResizeWatch(io: std.Io) !void {
    _ = io;

    if (resizeWatch.thread != null) return;

    resizeWatch.running.store(true, .release);
    resizeWatch.thread = std.Thread.spawn(.{}, watchForResize, .{}) catch |err| {
        resizeWatch.running.store(false, .release);
        return err;
    };
}

pub fn stopResizeWatch() void {
    resizeWatch.running.store(false, .release);

    const thread = resizeWatch.thread orelse return;
    resizeWatch.thread = null;
    thread.join();
}

fn watchForResize() void {
    var threadedIo = std.Io.Threaded.init_single_threaded;
    const io = threadedIo.io();

    var lastSize: ?utils.Size = getTerminalSize(io) catch null;

    while (resizeWatch.running.load(.acquire)) {
        std.Io.sleep(io, .fromMilliseconds(resize_poll_interval_ms), .awake) catch return;

        const size = getTerminalSize(io) catch continue;
        if (lastSize) |previous| {
            if (previous.width == size.width and previous.height == size.height) continue;
        }
        lastSize = size;

        globalMod.signalResize();
    }
}

fn getConsoleMode(io: std.Io, file: std.Io.File) !windows.DWORD {
    var op = UserIo.GET_MODE;
    switch (try op.operate(io, file)) {
        .SUCCESS => return op.Data,
        else => return error.NotTerminalDevice,
    }
}

fn setConsoleMode(io: std.Io, file: std.Io.File, value: windows.DWORD) !void {
    var op = UserIo.SET_MODE(value);
    switch (try op.operate(io, file)) {
        .SUCCESS => {},
        else => return error.NotTerminalDevice,
    }
}

fn getCodePage(io: std.Io, which: UserIo.INFO.CP.MODE) !windows.UINT {
    var op = UserIo.GET_CP(which);
    switch (try op.operate(io, null)) {
        .SUCCESS => return op.Data.CodePage,
        else => return error.NotTerminalDevice,
    }
}

fn setCodePage(io: std.Io, which: UserIo.INFO.CP.MODE, codePage: windows.UINT) !void {
    var op = UserIo.SET_CP(which, codePage);
    switch (try op.operate(io, null)) {
        .SUCCESS => {},
        else => return error.NotTerminalDevice,
    }
}
