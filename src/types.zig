const std = @import("std");

pub fn setEnumBackingInt(comptime Enum: type, comptime tagType: type) type {
    const enumType = @typeInfo(Enum).@"enum";

    var fieldNames: [enumType.fields.len][]const u8 = undefined;
    var fieldValues: [enumType.fields.len]tagType = undefined;

    inline for (enumType.fields, 0..) |field, index| {
        fieldNames[index] = field.name;
        fieldValues[index] = @intCast(field.value);
    }

    return @Enum(
        tagType,
        if (enumType.is_exhaustive) .exhaustive else .nonexhaustive,
        &fieldNames,
        &fieldValues,
    );
}

pub fn structFieldsToType(comptime Struct: type, comptime ToType: type) type {
    const structType = @typeInfo(Struct).@"struct";

    var fieldNames: [structType.fields.len][]const u8 = undefined;
    var fieldTypes: [structType.fields.len]type = undefined;
    var fieldAttributes: [structType.fields.len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (structType.fields, 0..) |field, index| {
        fieldNames[index] = field.name;
        fieldTypes[index] = ToType;
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

pub fn appendFieldToStruct(
    comptime Struct: type,
    comptime newField: struct {
        name: []const u8,
        type: type,
        attributes: std.builtin.Type.StructField.Attributes,
    },
) type {
    const structType = @typeInfo(Struct).@"struct";

    var fieldNames: [structType.fields.len + 1][]const u8 = undefined;
    var fieldTypes: [structType.fields.len + 1]type = undefined;
    var fieldAttributes: [structType.fields.len + 1]std.builtin.Type.StructField.Attributes = undefined;

    inline for (structType.fields, 0..) |field, index| {
        fieldNames[index] = field.name;
        fieldTypes[index] = field.type;
        fieldAttributes[index] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
    }

    fieldNames[fieldNames.len - 1] = newField.name;
    fieldTypes[fieldTypes.len - 1] = newField.type;
    fieldAttributes[fieldAttributes.len - 1] = newField.attributes;

    return @Struct(
        structType.layout,
        structType.backing_integer,
        &fieldNames,
        &fieldTypes,
        &fieldAttributes,
    );
}

pub fn setStructLayoutAndBackingInt(
    comptime Struct: type,
    comptime layout: std.builtin.Type.ContainerLayout,
    comptime backingInt: ?type,
) type {
    const structType = @typeInfo(Struct).@"struct";

    var fieldNames: [structType.fields.len][]const u8 = undefined;
    var fieldTypes: [structType.fields.len]type = undefined;
    var fieldAttributes: [structType.fields.len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (structType.fields, 0..) |field, index| {
        fieldNames[index] = field.name;
        fieldTypes[index] = field.type;
        fieldAttributes[index] = .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        };
    }

    return @Struct(
        layout,
        backingInt,
        &fieldNames,
        &fieldTypes,
        &fieldAttributes,
    );
}

pub fn changeFieldType(comptime Struct: type, comptime fieldName: []const u8, comptime ToType: type) type {
    const structType = @typeInfo(Struct).@"struct";

    if (!@hasField(Struct, fieldName)) @compileError("Expected struct to have field " ++ fieldName);

    var fieldNames: [structType.fields.len][]const u8 = undefined;
    var fieldTypes: [structType.fields.len]type = undefined;
    var fieldAttributes: [structType.fields.len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (structType.fields, 0..) |field, index| {
        fieldNames[index] = field.name;
        fieldTypes[index] = if (std.mem.eql(u8, fieldName, field.name))
            ToType
        else
            field.type;

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

pub fn tupleFromFnParams(comptime Func: type, comptime skip: usize) type {
    const funcType = @typeInfo(Func).@"fn";

    if (skip > funcType.params.len) @compileError("Expected skip <= fields.len");

    var tupleTypes: [funcType.params.len - skip]type = undefined;

    inline for (funcType.params[skip..], 0..) |param, index| {
        if (param.type == null) @compileError("Expected known param type");
        tupleTypes[index] = param.type.?;
    }

    return @Tuple(&tupleTypes);
}

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
