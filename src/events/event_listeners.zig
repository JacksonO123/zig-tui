const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("../types.zig");

const EventSystemError = error{
    BaseArgsNotInitialized,
};

const BaseArgInstance = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtable: struct {
        destroy: *const fn (*anyopaque, Allocator) void,
        call: *const fn (*anyopaque, *const anyopaque, *const anyopaque) void,
    },

    pub fn init(
        allocator: Allocator,
        value: anytype,
        comptime HandlerType: type,
        comptime AdditionalArgsType: type,
    ) !Self {
        const ArgsType = @TypeOf(value);
        const ptr = try allocator.create(ArgsType);
        ptr.* = value;

        const Funcs = struct {
            fn destroy(localPtr: *anyopaque, localAllocator: Allocator) void {
                const baseArgs: *ArgsType = @ptrCast(@alignCast(localPtr));
                localAllocator.destroy(baseArgs);
            }

            fn call(
                localPtr: *anyopaque,
                handlerPtr: *const anyopaque,
                argsPtr: *const anyopaque,
            ) void {
                const baseArgs: *ArgsType = @ptrCast(@alignCast(localPtr));
                const args: *const AdditionalArgsType = @ptrCast(@alignCast(argsPtr));
                const handler: HandlerType = @ptrCast(@alignCast(handlerPtr));
                @call(.auto, handler, baseArgs.* ++ args.*);
            }
        };

        return .{
            .ptr = ptr,
            .vtable = .{
                .destroy = Funcs.destroy,
                .call = Funcs.call,
            },
        };
    }

    pub fn destroy(self: Self, allocator: Allocator) void {
        self.vtable.destroy(self.ptr, allocator);
    }

    pub fn callHandlerWithArgs(
        self: Self,
        handler: *const anyopaque,
        args: *const anyopaque,
    ) void {
        self.vtable.call(self.ptr, handler, args);
    }
};

pub fn EventListenerCollection(comptime RegisterEvents: type) type {
    return struct {
        const Self = @This();
        const ListenerList = std.ArrayList(*const anyopaque);
        const ListenerMap = std.StringHashMap(*ListenerList);
        const CollectionType = enum { Preserved, Temporary };

        allocator: Allocator,
        baseArgMap: std.StringHashMap(BaseArgInstance),
        preservedListeners: *ListenerMap,
        temporaryListeners: *ListenerMap,

        pub fn init(gpa: Allocator) !Self {
            const preservedListenersPtr = try gpa.create(ListenerMap);
            preservedListenersPtr.* = ListenerMap.init(gpa);

            const temporaryListenersPtr = try gpa.create(ListenerMap);
            temporaryListenersPtr.* = ListenerMap.init(gpa);

            const baseArgMap = std.StringHashMap(BaseArgInstance).init(gpa);

            return .{
                .allocator = gpa,
                .baseArgMap = baseArgMap,
                .preservedListeners = preservedListenersPtr,
                .temporaryListeners = temporaryListenersPtr,
            };
        }

        pub fn deinit(self: *Self) void {
            self.deinitListenerCollection(self.preservedListeners);
            self.deinitListenerCollection(self.temporaryListeners);

            var argIt = self.baseArgMap.valueIterator();
            while (argIt.next()) |argInst| {
                argInst.destroy(self.allocator);
            }
            self.baseArgMap.deinit();
        }

        fn deinitListenerCollection(self: *Self, collection: *ListenerMap) void {
            var collectionIt = collection.valueIterator();
            while (collectionIt.next()) |value| {
                value.*.deinit(self.allocator);
                self.allocator.destroy(value.*);
            }

            collection.deinit();
            self.allocator.destroy(collection);
        }

        pub fn registerBaseArgs(self: *Self, argValues: anytype) !void {
            inline for (argValues) |value| {
                const RegisteredTypes = @FieldType(RegisterEvents, value.@"0");
                const ValueType = RegisteredTypes.BaseArgs;
                const typedValue: ValueType = value.@"1";
                const argInst = try BaseArgInstance.init(
                    self.allocator,
                    typedValue,
                    RegisteredTypes.Handler,
                    RegisteredTypes.Args,
                );
                try self.baseArgMap.put(value.@"0", argInst);
            }
        }

        pub fn on(
            self: *Self,
            comptime name: []const u8,
            comptime handler: @FieldType(RegisterEvents, name).Handler,
        ) !void {
            if (!self.baseArgMap.contains(name)) {
                return EventSystemError.BaseArgsNotInitialized;
            }

            if (self.preservedListeners.get(name)) |listeners| {
                try listeners.append(self.allocator, @ptrCast(handler));
            } else {
                var listeners = try self.allocator.create(ListenerList);
                listeners.* = .empty;
                try listeners.append(self.allocator, @ptrCast(handler));
                try self.preservedListeners.put(name, listeners);
            }
        }

        pub fn emit(
            self: *Self,
            comptime name: []const u8,
            payload: @FieldType(RegisterEvents, name).Args,
        ) !void {
            const baseArgs = self.baseArgMap.get(name) orelse
                return EventSystemError.BaseArgsNotInitialized;
            if (self.preservedListeners.get(name)) |listeners| {
                for (listeners.items) |listener| {
                    baseArgs.callHandlerWithArgs(listener, @ptrCast(&payload));
                }
            }
        }
    };
}

fn Event(comptime BaseArgsType: type, comptime ArgsType: type) type {
    return struct {
        pub const BaseArgs = BaseArgsType;
        pub const Args = ArgsType;
        pub const Handler = *const @Fn(
            &types.tupleToTypeSlice(types.combineTuples(BaseArgs, Args)),
            &@splat(.{}),
            void,
            .{},
        );
    };
}

pub const EventDescription = struct {
    name: []const u8,
    baseArgs: type,
    args: type,
};

pub fn formatRegisteredEvents(comptime eventDescription: []const EventDescription) type {
    var fieldNames: [eventDescription.len][]const u8 = undefined;
    var fieldTypes: [eventDescription.len]type = undefined;

    inline for (eventDescription, 0..) |description, index| {
        fieldNames[index] = description.name;
        fieldTypes[index] = Event(description.baseArgs, description.args);
    }

    const res = @Struct(.auto, null, &fieldNames, &fieldTypes, &@splat(.{}));
    return res;
}
