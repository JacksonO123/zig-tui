const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EventListener = struct {
    ptr: *anyopaque,
    vtable: *const struct {
        call: *const fn (*anyopaque, *anyopaque) void,
        destroy: *const fn (*anyopaque, Allocator) void,
    },
};

pub const EventListenerCollection = struct {
    const Self = @This();
    const ListenerCollection = std.StringHashMap(*std.ArrayList(EventListener));

    allocator: Allocator,
    preservedListeners: *ListenerCollection,

    pub fn init(gpa: Allocator) !Self {
        const preservedListeners = ListenerCollection.init(gpa);
        const preservedListenersPtr = try gpa.create(ListenerCollection);
        preservedListenersPtr.* = preservedListeners;

        return .{
            .allocator = gpa,
            .preservedListeners = preservedListenersPtr,
        };
    }

    pub fn deinit(self: *Self) void {
        var preservedListenersValueIt = self.preservedListeners.valueIterator();
        while (preservedListenersValueIt.next()) |value| {
            for (value.*.items) |*eventInfo| {
                eventInfo.vtable.destroy(eventInfo.ptr, self.allocator);
            }

            value.*.deinit(self.allocator);
            self.allocator.destroy(value.*);
        }

        self.preservedListeners.deinit();
        self.allocator.destroy(self.preservedListeners);
    }

    pub fn onEvent(
        self: *Self,
        comptime AdditionalArgs: type,
        name: []const u8,
        comptime handler: anytype,
        contextArgs: anytype,
    ) !void {
        const Args = @TypeOf(contextArgs);
        const argsPtr = try self.allocator.create(Args);
        argsPtr.* = contextArgs;

        const Funcs = struct {
            fn call(ptr: *anyopaque, additionalArgsOpaque: *anyopaque) void {
                const initialArgs: *Args = @ptrCast(@alignCast(ptr));
                const additionalArgs: *AdditionalArgs = @ptrCast(@alignCast(additionalArgsOpaque));
                @call(.auto, handler, .{ initialArgs.*, additionalArgs.* });
            }
            fn destroy(ptr: *anyopaque, allocator: Allocator) void {
                const initialArgs: *Args = @ptrCast(@alignCast(ptr));
                allocator.destroy(initialArgs);
            }
        };

        const listener = EventListener{
            .ptr = argsPtr,
            .vtable = &.{
                .call = Funcs.call,
                .destroy = Funcs.destroy,
            },
        };

        if (self.preservedListeners.get(name)) |events| {
            try events.append(self.allocator, listener);
        } else {
            var list: std.ArrayList(EventListener) = .empty;
            try list.append(self.allocator, listener);
            const listPtr = try self.allocator.create(std.ArrayList(EventListener));
            listPtr.* = list;
            try self.preservedListeners.put(name, listPtr);
        }
    }

    pub fn emitEvent(self: *Self, name: []const u8, args: anytype) void {
        if (self.preservedListeners.get(name)) |handlers| {
            for (handlers.items) |handler| {
                var argsCpy = args;
                handler.vtable.call(handler.ptr, @ptrCast(&argsCpy));
            }
        }
    }
};
