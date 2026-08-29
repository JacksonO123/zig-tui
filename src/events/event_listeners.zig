const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("../types.zig");

const EventSystemError = error{
    BaseArgsNotInitialized,
};

const ListenerInstancePayload = struct {
    baseArgs: *anyopaque,
    handler: *const anyopaque,
};

const ListenerInstance = struct {
    const Self = @This();

    payload: ListenerInstancePayload,
    vtable: struct {
        destroy: *const fn (*ListenerInstancePayload, Allocator) void,
        call: *const fn (*ListenerInstancePayload, *const anyopaque) anyerror!void,
    },

    pub fn init(
        allocator: Allocator,
        comptime HandlerType: type,
        comptime AdditionalArgsType: type,
        comptime handler: HandlerType,
        baseArg: anytype,
    ) !Self {
        const ArgsType = @TypeOf(baseArg);
        const ptr = try allocator.create(ArgsType);
        ptr.* = baseArg;

        const Funcs = struct {
            fn destroy(payload: *ListenerInstancePayload, localAllocator: Allocator) void {
                const baseArgs: *ArgsType = @ptrCast(@alignCast(payload.baseArgs));
                localAllocator.destroy(baseArgs);
            }

            fn call(
                payload: *ListenerInstancePayload,
                argsPtr: *const anyopaque,
            ) !void {
                const baseArgs: *ArgsType = @ptrCast(@alignCast(payload.baseArgs));
                const args: *const AdditionalArgsType = @ptrCast(@alignCast(argsPtr));
                const localHandler: HandlerType = @ptrCast(@alignCast(payload.handler));
                try @call(.auto, localHandler, baseArgs.* ++ args.*);
            }
        };

        return .{
            .payload = .{
                .baseArgs = ptr,
                .handler = handler,
            },
            .vtable = .{
                .destroy = Funcs.destroy,
                .call = Funcs.call,
            },
        };
    }

    pub fn destroy(self: *Self, allocator: Allocator) void {
        self.vtable.destroy(&self.payload, allocator);
    }

    pub fn call(
        self: *Self,
        args: *const anyopaque,
    ) !void {
        try self.vtable.call(&self.payload, args);
    }
};

pub fn EventListenerCollection(comptime RegisterEvents: type) type {
    return struct {
        const Self = @This();
        const ListenerList = std.ArrayList(ListenerInstance);
        const ListenerMap = std.StringHashMapUnmanaged(*ListenerList);

        renderAlloc: Allocator,
        preservedArena: std.heap.ArenaAllocator,
        preservedListeners: ListenerMap = .empty,
        tempListeners: ListenerMap = .empty,

        pub const RegisteredEvents = RegisterEvents;

        pub fn init(renderAlloc: Allocator) !Self {
            const preservedArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

            return .{
                .renderAlloc = renderAlloc,
                .preservedArena = preservedArena,
            };
        }

        pub fn deinit(self: *Self) void {
            self.preservedArena.deinit();
        }

        pub fn removeTemporaryListeners(self: *Self) !void {
            self.tempListeners = .empty;
        }

        fn createListener(
            allocator: Allocator,
            comptime name: []const u8,
            baseArgs: anytype,
            comptime handler: *const @FieldType(
                RegisterEvents,
                name,
            ).getHandler(@TypeOf(baseArgs)),
        ) !ListenerInstance {
            const registeredTypes = @FieldType(RegisterEvents, name);
            const listenerInstance = try ListenerInstance.init(
                allocator,
                *const registeredTypes.getHandler(@TypeOf(baseArgs)),
                registeredTypes.Args,
                handler,
                baseArgs,
            );

            return listenerInstance;
        }

        fn onImpl(
            allocator: Allocator,
            map: *ListenerMap,
            comptime name: []const u8,
            baseArgs: anytype,
            comptime handler: anytype,
        ) !void {
            const instance = try createListener(
                allocator,
                name,
                baseArgs,
                handler,
            );

            if (map.get(name)) |listeners| {
                try listeners.append(allocator, instance);
            } else {
                var listeners = try allocator.create(ListenerList);
                listeners.* = .empty;
                try listeners.append(allocator, instance);
                try map.put(allocator, name, listeners);
            }
        }

        pub fn on(
            self: *Self,
            comptime name: []const u8,
            baseArgs: anytype,
            comptime handler: anytype,
        ) !void {
            try onImpl(
                self.preservedArena.allocator(),
                &self.preservedListeners,
                name,
                baseArgs,
                handler,
            );
        }

        pub fn onTemporary(
            self: *Self,
            comptime name: []const u8,
            baseArgs: anytype,
            comptime handler: anytype,
        ) !void {
            try onImpl(self.renderAlloc.allocator(), &self.tempListeners, name, baseArgs, handler);
        }

        fn emitImpl(
            map: *ListenerMap,
            comptime name: []const u8,
            payload: @FieldType(RegisterEvents, name).Args,
        ) !void {
            if (map.get(name)) |listeners| {
                for (listeners.items) |*listener| {
                    try listener.call(@ptrCast(&payload));
                }
            }
        }

        pub fn emit(self: *Self, comptime name: []const u8, payload: anytype) !void {
            try emitImpl(&self.preservedListeners, name, payload);
            try emitImpl(&self.tempListeners, name, payload);
        }
    };
}

fn Event(comptime ArgsType: type) type {
    return struct {
        pub const Args = ArgsType;

        pub fn getHandler(comptime BaseArgs: type) type {
            return @Fn(
                &types.tupleToTypeSlice(types.combineTuples(BaseArgs, Args)),
                &@splat(.{}),
                anyerror!void,
                .{},
            );
        }
    };
}

pub const EventDescription = struct {
    name: []const u8,
    args: type,
};

pub fn formatRegisteredEvents(comptime eventDescription: []const EventDescription) type {
    var fieldNames: [eventDescription.len][]const u8 = undefined;
    var fieldTypes: [eventDescription.len]type = undefined;

    inline for (eventDescription, 0..) |description, index| {
        fieldNames[index] = description.name;
        fieldTypes[index] = Event(description.args);
    }

    const res = @Struct(.auto, null, &fieldNames, &fieldTypes, &@splat(.{}));
    return res;
}
