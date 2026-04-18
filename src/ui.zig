pub const UIElementTypes = enum {
    Text,
};

pub const UIElement = union(UIElementTypes) {
    Text: []const u8,
};
