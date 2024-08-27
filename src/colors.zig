const nativeToBig = @import("std").mem.nativeToBig;
pub const Color = @cImport({
    @cInclude("raylib.h");
}).Color;

pub fn int2Color(int: u32) Color {
    var val = int;
    if (val < 0x1_00_00_00) {
        val = (val << 8) + 0xFF;
    }
    return @bitCast(nativeToBig(u32, val));
}

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
