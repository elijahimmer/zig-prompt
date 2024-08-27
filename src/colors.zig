const nativeToBig = @import("std").mem.nativeToBig;
const Color = @import("raylib").Color;

pub const main: Color = @bitCast(nativeToBig(u32, 0x191724FF));
pub const surface: Color = @bitCast(nativeToBig(u32, 0x1f1d2eFF));
pub const overlay: Color = @bitCast(nativeToBig(u32, 0x26233aFF));
pub const muted: Color = @bitCast(nativeToBig(u32, 0x908caaFF));
pub const text: Color = @bitCast(nativeToBig(u32, 0xe0def4FF));
pub const love: Color = @bitCast(nativeToBig(u32, 0xeb6f92FF));
pub const gold: Color = @bitCast(nativeToBig(u32, 0xf6c177FF));
pub const rose: Color = @bitCast(nativeToBig(u32, 0xebbcbaFF));
pub const pine: Color = @bitCast(nativeToBig(u32, 0x31748fFF));
pub const foam: Color = @bitCast(nativeToBig(u32, 0x9ccfd8FF));
pub const iris: Color = @bitCast(nativeToBig(u32, 0xc4a7e7FF));
pub const hl_low: Color = @bitCast(nativeToBig(u32, 0x21202eFF));
pub const hl_med: Color = @bitCast(nativeToBig(u32, 0x403d52FF));
pub const hl_high: Color = @bitCast(nativeToBig(u32, 0x524f67FF));
