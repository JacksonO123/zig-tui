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

pub const Borders = struct {
    square: BorderChars,
    rounded: BorderChars,
};

pub const borders: Borders = .{
    .square = BorderChars{
        .horizontal = "─",
        .vertical = "│",
        .corners = .{
            .topLeft = "┌",
            .topRight = "┐",
            .bottomLeft = "└",
            .bottomRight = "┘",
        },
    },
    .rounded = BorderChars{
        .horizontal = "─",
        .vertical = "│",
        .corners = .{
            .topLeft = "╭",
            .topRight = "╮",
            .bottomLeft = "╰",
            .bottomRight = "╯",
        },
    },
};

const BorderStylesVariant = enum {
    const Self = @This();

    Square,
    Rounded,
    None,

    pub fn getChars(self: Self) ?BorderChars {
        return switch (self) {
            .Square => borders.square,
            .Rounded => borders.rounded,
            .None => null,
        };
    }
};

const BoldVariants = enum {
    Bold,
    None,
};

const ElementBorderStyles = struct {
    const Self = @This();

    borderVariant: BorderStylesVariant = .None,

    pub fn getChars(self: Self) ?BorderChars {
        return self.borderVariant.getChars();
    }
};

pub const Styles = struct {
    const Self = @This();

    styles: struct {
        border: ElementBorderStyles = .{},
        padding: struct {
            paddingX: u16 = 0,
            paddingY: u16 = 0,
        } = .{},
        boldState: BoldVariants = .None,
    } = .{},

    pub const default: Self = .{};

    pub fn toSimpleStyles(self: Self) SimpleDataStyle {
        return .{
            .bold = self.styles.boldState == .Bold,
        };
    }

    pub fn border(self: *Self, style: BorderStylesVariant) *ElementBorderStyles {
        self.styles.border.borderVariant = style;
        return &self.styles.border;
    }

    pub fn hasBorder(self: Self) bool {
        return self.styles.border.borderVariant != .None;
    }

    pub fn padding(self: *Self, amount: u16) void {
        self.styles.padding.paddingX = amount;
        self.styles.padding.paddingY = amount;
    }

    pub fn paddingX(self: *Self, amount: u16) void {
        self.styles.padding.paddingX = amount;
    }

    pub fn paddingY(self: *Self, amount: u16) void {
        self.styles.padding.paddingY = amount;
    }

    pub fn bold(self: *Self) void {
        self.styles.boldState = .Bold;
    }
};

pub const SimpleDataStyle = struct {
    bold: bool = false,
};
