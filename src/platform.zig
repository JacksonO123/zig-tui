const builtin = @import("builtin");

const impl = switch (builtin.os.tag) {
    .windows => @import("platform/windows.zig"),
    .freestanding, .other, .wasi, .emscripten => @compileError(
        "zig-tui has no terminal backend for " ++ @tagName(builtin.os.tag),
    ),
    else => @import("platform/posix.zig"),
};

pub const enterRawMode = impl.enterRawMode;

pub const exitRawMode = impl.exitRawMode;

pub const getTerminalSize = impl.getTerminalSize;

pub const startResizeWatch = impl.startResizeWatch;

pub const stopResizeWatch = impl.stopResizeWatch;
