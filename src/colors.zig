// This is ARGB format in little endian
pub const Color = packed struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8,
};

/// turns a rgb int into a color
pub fn rgb2Color(int: u24) Color {
    var val: u32 = int;
    val |= 0xFF_00_00_00;
    return @bitCast(val);
}

test rgb2Color {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(
        @as(u32, @bitCast(rgb2Color(0x112233))),
        0xFF112233,
    );
}

pub fn rgba2argb(rgba: Color) Color {
    var color = rgba;
    std.mem.rotate(u8, std.mem.asBytes(&color), 1);
    return color;
}

test rgba2argb {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(
        0x11223344,
        @as(u32, @bitCast(rgba2argb(@bitCast(@as(u32, 0x22334411))))),
    );
}

pub const Str2ColorError = error{ @"Hex string is empty", @"Illegal Character in hex string", @"Hex string incorrect length", @"Hex string too long" };

/// turns a rgba hex string into a color
pub fn str2Color(str: []const u8) Str2ColorError!Color {
    if (str.len == 0) return error.@"Hex string is empty";

    inline for (COLOR_LIST) |color| {
        if (std.ascii.eqlIgnoreCase(color.name, str)) return color.color;
    }

    //pub const ColorListElement = struct { color: Color, name: []const u8 };

    var color: u32 = 0;

    const start_idx = @intFromBool(str[0] == '#');
    var digit_count: u4 = 0;

    for (str[start_idx..]) |char| {
        if (digit_count >= 8) return error.@"Hex string too long";

        if (char == '_') continue;

        if (!ascii.isHex(char)) return error.@"Illegal Character in hex string";

        const c = ascii.toUpper(char);

        color <<= 4;
        color |= @as(u4, @truncate(c));
        if ('A' <= c and c <= 'F') color += 9;

        digit_count += 1;
    }

    if (digit_count == 4) {
        assert(color <= std.math.maxInt(u16));
        color =
            ((color & 0x00_0F) << 24) | // alpha
            ((color & 0xF0_00) << 4) | // red
            ((color & 0x0F_00)) | // green
            ((color & 0x00_F0) >> 4); // blue

        color |= color << 4;

        return @bitCast(color);
    } else if (digit_count == 3) {
        assert(color <= std.math.maxInt(u16));
        color =
            ((color & 0x0F_00) << 8) | // red
            ((color & 0x00_F0) << 4) | // green
            ((color & 0x00_0F)); // blue

        color |= 0x0F_00_00_00;
        color |= color << 4;

        return @bitCast(color);
    } else if (digit_count == 6) {
        return @bitCast(color | 0xFF_00_00_00); // add opaque to alpha-less codes
    } else if (digit_count == 8) {
        return rgba2argb(@bitCast(color));
    } else {
        return error.@"Hex string incorrect length";
    }
}

test str2Color {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(0x44112233, @as(u32, @bitCast(try str2Color("11223344"))));
    try expectEqual(0xFF112233, @as(u32, @bitCast(try str2Color("112233"))));
    try expectEqual(0x44112233, @as(u32, @bitCast(try str2Color("1234"))));
    try expectEqual(0xFF112233, @as(u32, @bitCast(try str2Color("123"))));
}

// assumes compositing onto opaque (alpha == 255)
pub fn composite(bg: Color, fg: Color) Color {
    const ratio = @as(f32, @floatFromInt(fg.a)) / 255.0;
    const ratio_old = @max(1.0 - ratio, 0.0);

    const r_fg, const g_fg, const b_fg = .{ @as(f32, @floatFromInt(fg.r)), @as(f32, @floatFromInt(fg.g)), @as(f32, @floatFromInt(fg.b)) };
    const r_bg, const g_bg, const b_bg = .{ @as(f32, @floatFromInt(bg.r)), @as(f32, @floatFromInt(bg.g)), @as(f32, @floatFromInt(bg.b)) };

    return .{
        .a = bg.a +| fg.a,
        .r = @intFromFloat(ratio * r_fg + ratio_old * r_bg),
        .g = @intFromFloat(ratio * g_fg + ratio_old * g_bg),
        .b = @intFromFloat(ratio * b_fg + ratio_old * b_bg),
    };
}

test composite {
    const expect = std.testing.expect;

    const compos = @as(u32, @bitCast(composite(all_colors.black, all_colors.main)));
    const color = @as(u32, @bitCast(all_colors.main));

    try expect(compos == color);
}

pub const all_colors = struct {
    pub const clear: Color = @bitCast(@as(u32, 0));
    pub const white: Color = @bitCast(~@as(u32, 0));
    pub const black: Color = @bitCast(@as(u32, 0xFF_00_00_00));
    pub const main: Color = rgb2Color(0x191724);
    pub const surface: Color = rgb2Color(0x1f1d2e);
    pub const overlay: Color = rgb2Color(0x26233a);
    pub const muted: Color = rgb2Color(0x908caa);
    pub const text: Color = rgb2Color(0xe0def4);
    pub const love: Color = rgb2Color(0xeb6f92);
    pub const gold: Color = rgb2Color(0xf6c177);
    pub const rose: Color = rgb2Color(0xebbcba);
    pub const pine: Color = rgb2Color(0x31748f);
    pub const foam: Color = rgb2Color(0x9ccfd8);
    pub const iris: Color = rgb2Color(0xc4a7e7);
    pub const hl_low: Color = rgb2Color(0x21202e);
    pub const hl_med: Color = rgb2Color(0x403d52);
    pub const hl_high: Color = rgb2Color(0x524f67);
};

pub const ColorListElement = struct { color: Color, name: []const u8 };
pub const COLOR_LIST: [@typeInfo(all_colors).Struct.decls.len]ColorListElement = generate_color_list(all_colors);

fn generate_color_list(obj: anytype) [@typeInfo(obj).Struct.decls.len]ColorListElement {
    const type_info = @typeInfo(obj);

    assert(type_info.Struct.decls.len > 0);
    var list: [type_info.Struct.decls.len]ColorListElement = undefined;

    inline for (type_info.Struct.decls, 0..) |decl, idx| {
        list[idx] = .{
            .color = @field(obj, decl.name),
            .name = decl.name,
        };
    }

    return list;
}

const std = @import("std");
const assert = std.debug.assert;
const ascii = std.ascii;
