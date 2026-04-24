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

pub const Color = enum {
    const Self = @This();

    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    White,
    None,
};

pub const StyleConfig = struct {
    border: BorderStylesVariant = .None,
    padding: struct {
        paddingLeft: u16 = 0,
        paddingRight: u16 = 0,
        paddingTop: u16 = 0,
        paddingBottom: u16 = 0,
    } = .{},
    boldState: ActiveState = .None,
    underlineState: ActiveState = .None,
    italicState: ActiveState = .None,
    fg: Color = .None,
    bg: Color = .None,
};

pub const Styles = struct {
    const Self = @This();

    styles: StyleConfig = .{},

    pub const default: Self = .{};

    pub fn toSimpleStyles(self: Self) SimpleDataStyle {
        return .{
            .bold = self.styles.boldState == .Active,
            .underline = self.styles.underlineState == .Active,
            .italic = self.styles.italicState == .Active,
            .fg = self.styles.fg,
            .bg = self.styles.bg,
        };
    }

    pub fn hasBorder(self: Self) bool {
        return self.styles.border != .None;
    }

    pub fn fg(self: *Self, color: Color) *Self {
        self.styles.fg = color;
        return self;
    }

    pub fn bg(self: *Self, color: Color) *Self {
        self.styles.bg = color;
        return self;
    }

    pub fn border(self: *Self, style: BorderStylesVariant) *Self {
        self.styles.border = style;
        return self;
    }

    pub fn padding(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingLeft = amount;
        self.styles.padding.paddingRight = amount;
        self.styles.padding.paddingTop = amount;
        self.styles.padding.paddingBottom = amount;
        return self;
    }

    pub fn paddingLeft(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingLeft = amount;
        return self;
    }

    pub fn paddingRight(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingRight = amount;
        return self;
    }

    pub fn paddingTop(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingTop = amount;
        return self;
    }

    pub fn paddingBottom(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingBottom = amount;
        return self;
    }

    pub fn paddingX(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingLeft = amount;
        self.styles.padding.paddingRight = amount;
        return self;
    }

    pub fn paddingY(self: *Self, amount: u16) *Self {
        self.styles.padding.paddingTop = amount;
        self.styles.padding.paddingBottom = amount;
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
    fg: Color = .None,
    bg: Color = .None,
};
