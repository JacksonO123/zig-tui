const std = @import("std");

pub fn setEnumBackingInt(comptime Enum: type, comptime tagType: type) type {
    const enumType = if (@typeInfo(Enum) != .@"enum")
        @compileError("Expected enum")
    else
        @typeInfo(Enum).@"enum";

    var fieldNames: [enumType.fields.len][]const u8 = undefined;
    var fieldValues: [enumType.fields.len]tagType = undefined;

    for (enumType.fields, 0..) |field, index| {
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
    const structTypeBefore = @typeInfo(Struct);
    if (structTypeBefore != .@"struct") @compileError("Expected struct for index transform");
    const structType = structTypeBefore.@"struct";

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
    const structTypeBefore = @typeInfo(Struct);
    if (structTypeBefore != .@"struct") @compileError("Expected struct for index transform");
    const structType = structTypeBefore.@"struct";

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
    const structTypeBefore = @typeInfo(Struct);
    if (structTypeBefore != .@"struct") @compileError("Expected struct for index transform");
    const structType = structTypeBefore.@"struct";

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
    const structType = if (@typeInfo(Struct) != .@"struct")
        @compileError("Expected struct")
    else
        @typeInfo(Struct).@"struct";

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
