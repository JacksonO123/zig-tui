const std = @import("std");

pub fn tupleToTypeSlice(comptime Tuple: type) [@typeInfo(Tuple).@"struct".fields.len]type {
    const tupleType = @typeInfo(Tuple).@"struct";
    var types: [tupleType.fields.len]type = undefined;

    inline for (tupleType.fields, 0..) |field, index| {
        types[index] = field.type;
    }

    return types;
}

pub fn combineTuples(comptime Tuple1: type, comptime Tuple2: type) type {
    const tuple1Info = @typeInfo(Tuple1).@"struct";
    const tuple2Info = @typeInfo(Tuple2).@"struct";
    var types: [tuple1Info.fields.len + tuple2Info.fields.len]type = undefined;

    var index: usize = 0;
    for (tuple1Info.fields) |field| {
        defer index += 1;
        types[index] = field.type;
    }
    for (tuple2Info.fields) |field| {
        defer index += 1;
        types[index] = field.type;
    }

    return @Tuple(&types);
}

pub fn makeStructFieldsOptional(comptime Struct: type) type {
    const structType = @typeInfo(Struct).@"struct";

    var fieldNames: [structType.fields.len][]const u8 = undefined;
    var fieldTypes: [structType.fields.len]type = undefined;
    var fieldAttributes: [structType.fields.len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (structType.fields, 0..) |field, index| {
        fieldNames[index] = field.name;
        fieldTypes[index] = ?field.type;

        fieldAttributes[index] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
    }

    return @Struct(
        structType.layout,
        structType.backing_integer,
        &fieldNames,
        &fieldTypes,
        &fieldAttributes,
    );
}
