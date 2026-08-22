const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");

const ListenerDispatch = struct {
    const Self = @This();

    handler: *anyopaque,
    call: *const fn (*anyopaque, *anyopaque, *anyopaque) void,

    pub fn envoke(self: Self, baseArgsPtr: *anyopaque, additionalArgsPtr: *anyopaque) void {
        self.call(self.handler, baseArgsPtr, additionalArgsPtr);
    }
};

const EventListenerManagerPayload = struct {
    listeners: *std.ArrayList(ListenerDispatch),
    baseArgs: *anyopaque,
};

const EventListenerManager = struct {
    const Self = @This();

    ptr: *EventListenerManagerPayload,
    vtable: *const struct {
        addListener: *const fn (*EventListenerManagerPayload, Allocator, *anyopaque) anyerror!void,
        destroy: *const fn (*EventListenerManagerPayload, Allocator) void,
    },

    pub fn addListener(self: *Self, allocator: Allocator, baseArgs: *anyopaque) !void {
        self.vtable.addListener(self.ptr, allocator, baseArgs);
    }
};

pub const EventListenerCollection = struct {
    const Self = @This();
    const ManagerCollection = std.StringHashMap(EventListenerManager);
    const CollectionType = enum { Preserved, Temporary };

    allocator: Allocator,
    preservedListeners: *ManagerCollection,
    temporaryListeners: *ManagerCollection,

    pub fn init(gpa: Allocator) !Self {
        const preservedListeners = ManagerCollection.init(gpa);
        const preservedListenersPtr = try gpa.create(ManagerCollection);
        preservedListenersPtr.* = preservedListeners;

        const temporaryListeners = ManagerCollection.init(gpa);
        const temporaryListenersPtr = try gpa.create(ManagerCollection);
        temporaryListenersPtr.* = temporaryListeners;

        return .{
            .allocator = gpa,
            .preservedListeners = preservedListenersPtr,
            .temporaryListeners = temporaryListenersPtr,
        };
    }

    pub fn deinit(self: *Self) void {
        self.deinitListenerCollection(self.preservedListeners);
        self.deinitListenerCollection(self.temporaryListeners);
    }

    fn deinitListenerCollection(self: *Self, collection: *ManagerCollection) void {
        var collectionIt = collection.valueIterator();
        while (collectionIt.next()) |value| {
            value.vtable.destroy(value.ptr, self.allocator);
        }

        collection.deinit();
        self.allocator.destroy(collection);
    }

    pub fn register(
        self: *Self,
        comptime name: []const u8,
        comptime HandlerType: type,
        baseArgs: anytype,
    ) !void {
        if (@typeInfo(@TypeOf(baseArgs)) != .@"struct" or !@typeInfo(@TypeOf(baseArgs)).@"struct".is_tuple) {
            @compileError("Expected tuple for base args type");
        }

        if (self.preservedListeners.contains(name)) {
            return error.EventContractAlreadyInitialized;
        }

        const ArgsType = types.tupleFromFnParams(HandlerType, baseArgs.len);

        const BaseArgs = @TypeOf(baseArgs);
        const argsPtr = try self.allocator.create(BaseArgs);
        argsPtr.* = baseArgs;

        const listeners: std.ArrayList(ListenerDispatch) = .empty;
        const listenersPtr = try self.allocator.create(std.ArrayList(ListenerDispatch));
        listenersPtr.* = listeners;

        const Funcs = struct {
            fn addListener(
                payload: *EventListenerManagerPayload,
                allocator: Allocator,
                handlerPtr: *anyopaque,
            ) !void {
                const LocalFuncs = struct {
                    fn call(localHandlerPtr: *anyopaque, baseArgsPtr: *anyopaque, additionalArgsPtr: *anyopaque) void {
                        const handler: *HandlerType = @ptrCast(@alignCast(localHandlerPtr));
                        const localBaseArgs: *BaseArgs = @ptrCast(@alignCast(baseArgsPtr));
                        const additionalArgs: *ArgsType = @ptrCast(@alignCast(additionalArgsPtr));
                        @call(.auto, handler, localBaseArgs.* ++ additionalArgs.*);
                    }
                };

                const handler: *HandlerType = @ptrCast(@alignCast(handlerPtr));
                const listenerDispatch = ListenerDispatch{
                    .handler = handler,
                    .call = LocalFuncs.call,
                };

                try payload.listeners.append(allocator, listenerDispatch);
            }

            fn destroy(payload: *EventListenerManagerPayload, allocator: Allocator) void {
                const localBaseArgs: *BaseArgs = @ptrCast(@alignCast(payload.baseArgs));
                allocator.destroy(localBaseArgs);
                payload.listeners.deinit(allocator);
                allocator.destroy(payload.listeners);
                allocator.destroy(payload);
            }
        };

        const payload = EventListenerManagerPayload{
            .baseArgs = argsPtr,
            .listeners = listenersPtr,
        };
        const payloadPtr = try self.allocator.create(EventListenerManagerPayload);
        payloadPtr.* = payload;

        const manager = EventListenerManager{
            .ptr = payloadPtr,
            .vtable = &.{
                .addListener = Funcs.addListener,
                .destroy = Funcs.destroy,
            },
        };

        try self.preservedListeners.put(name, manager);
    }
};
