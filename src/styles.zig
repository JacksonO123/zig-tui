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

const ActiveState = enum {
    Active,
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
        boldState: ActiveState = .None,
        underlineState: ActiveState = .None,
        italicState: ActiveState = .None,
    } = .{},

    pub const default: Self = .{};

    pub fn toSimpleStyles(self: Self) SimpleDataStyle {
        return .{
            .bold = self.styles.boldState == .Active,
            .underline = self.styles.underlineState == .Active,
            .italic = self.styles.italicState == .Active,
        };
    }

    pub fn hasBorder(self: Self) bool {
        return self.styles.border.borderVariant != .None;
    }

    pub fn border(self: *Self, style: BorderStylesVariant) *Self {
        self.styles.border.borderVariant = style;
        return self;
    }

    pub fn padding(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingX = amount;
        self.styles.padding.paddingY = amount;
        return self;
    }

    pub fn paddingX(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingX = amount;
        return self;
    }

    pub fn paddingY(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingY = amount;
        return self;
    }

    pub fn bold(self: *Self) *Self {
        self.styles.boldState = .Active;
        return self;
    }

    pub fn underline(self: *Self) *Self {
        self.styles.underlineState = .Active;
        return self;
    }

    pub fn italic(self: *Self) *Self {
        self.styles.italicState = .Active;
        return self;
    }
};

pub const SimpleDataStyle = struct {
    bold: bool = false,
    underline: bool = false,
    italic: bool = false,
};
