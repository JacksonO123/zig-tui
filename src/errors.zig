const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

pub const InvalidUtf8 = error{InvalidUtf8};

pub const SetElementDimensionsError = InvalidUtf8 || Allocator.Error;

pub const GetCursorPosError = error{
    UnexpectedEOF,
    InvalidResponse,
} || Writer.Error || std.posix.ReadError;

pub const GetTermSizeError = error{FailedToGetSize};
