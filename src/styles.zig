const BorderCornerChars = struct {
    topLeft: []const u8,
    topRight: []const u8,
    bottomLeft: []const u8,
    bottomRight: []const u8,
};

const BorderChars = struct {
    horizontal: []const u8,
    vertical: []const u8,
    corners: BorderCornerChars,
};

const BorderStylesVariant = enum {
    Square,
    Rounded,
};

const BorderStyles = struct {
    square: BorderChars,
    rounded: BorderChars,
};

pub const Borders = struct {
    normal: BorderStyles,
};

pub const borders: Borders = .{
    .normal = BorderStyles{
        .square = .{
            .horizontal = "─",
            .vertical = "│",
            .corners = .{
                .topLeft = "┌",
                .topRight = "┐",
                .bottomLeft = "└",
                .bottomRight = "┘",
            },
        },
        .rounded = .{
            .horizontal = "─",
            .vertical = "│",
            .corners = .{
                .topLeft = "╭",
                .topRight = "╮",
                .bottomLeft = "╰",
                .bottomRight = "╯",
            },
        },
    },
};

pub const Styles = struct {
    const Self = @This();

    styles: struct {
        border: ?*const BorderChars = null,
    } = .{},

    pub const default: Self = .{};

    pub fn border(self: *Self, style: BorderStylesVariant) void {
        self.styles.border = switch (style) {
            .Square => &borders.normal.square,
            .Rounded => &borders.normal.rounded,
        };
    }
};
