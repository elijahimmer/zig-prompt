const nativeToBig = @import("std").mem.nativeToBig;
pub const Color = packed struct {
    a: u8,
    r: u8,
    b: u8,
    g: u8,
};

pub fn int2Color(int: u32) Color {
    var val = int;
    if (val < 0x1_00_00_00) val += 0xFF_00_00_00; // make it opaque if no alpha
    return @bitCast(val);
}

pub fn composite(bg: Color, fg: Color) Color {
    const ratio = @as(f32, @floatFromInt(fg.a)) / 255.0;
    const ratio_old = 1.0 - ratio;
    const r_fg, const g_fg, const b_fg = .{ @as(f32, @floatFromInt(fg.r)), @as(f32, @floatFromInt(fg.g)), @as(f32, @floatFromInt(fg.b)) };
    const r_bg, const g_bg, const b_bg = .{ @as(f32, @floatFromInt(bg.r)), @as(f32, @floatFromInt(bg.g)), @as(f32, @floatFromInt(bg.b)) };

    return .{
        .r = @intFromFloat(ratio * r_fg + ratio_old * r_bg),
        .g = @intFromFloat(ratio * g_fg + ratio_old * g_bg),
        .b = @intFromFloat(ratio * b_fg + ratio_old * b_bg),
        .a = bg.a +| fg.a,
    };
}

//pub fn composite(self, onto: Self) -> Self {
//}

pub const main: Color = int2Color(0x191724);
pub const surface: Color = int2Color(0x1f1d2e);
pub const overlay: Color = int2Color(0x26233a);
pub const muted: Color = int2Color(0x908caa);
pub const text: Color = int2Color(0xe0def4);
pub const love: Color = int2Color(0xeb6f92);
pub const gold: Color = int2Color(0xf6c177);
pub const rose: Color = int2Color(0xebbcba);
pub const pine: Color = int2Color(0x31748f);
pub const foam: Color = int2Color(0x9ccfd8);
pub const iris: Color = int2Color(0xc4a7e7);
pub const hl_low: Color = int2Color(0x21202e);
pub const hl_med: Color = int2Color(0x403d52);
pub const hl_high: Color = int2Color(0x524f67);
