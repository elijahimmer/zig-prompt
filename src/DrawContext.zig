const Vector = struct {
    x: u31,
    y: u31,
};

pub const ScreenBuffer = struct {
    fd: std.posix.fd_t,
    screen: []u8,
    height: u31,
    width: u31,
};

pub const DrawContext = @This();

config: *const Config,
freetype_lib: freetype.Library,
font_face: freetype.Face,

pub fn init(config: *const Config) !DrawContext {
    const freetype_lib = try freetype.Library.init();
    log.info("freetype version: {}.{}.{}", freetype_lib.version());

    // TODO: allow for custom font
    const font_face = try freetype_lib.createFaceMemory(assets.font_data, 0);
    log.info("font family: {s}, style: {s}", .{ font_face.familyName() orelse "none", font_face.styleName() orelse "none" });

    try font_face.setPixelSizes((config.font_size * 92) / 72, 0);

    return .{
        .config = config,
        .freetype_lib = freetype_lib,
        .font_face = font_face,
    };
}

pub fn createScreenBuffer(self: *const DrawContext) !ScreenBuffer {
    const height = self.config.height orelse height: {
        const font_height: u31 = @as(u31, @intCast(self.font_face.height() >> 6));
        const font_lines: u31 = @intCast(self.config.options.len);

        break :height font_height * font_lines * 3;
    };
    const width = self.config.width orelse width: {
        const font_advance_width: u31 = @as(u31, @intCast(self.font_face.maxAdvanceWidth() >> 6));
        var max_line_length: u31 = 0;
        for (self.config.options) |option| {
            const line_len: u31 = @intCast(option.key.len + option.desc.len);
            max_line_length = @intCast(@max(max_line_length, line_len));
        }
        max_line_length += @intCast(self.config.seperator.len);

        break :width font_advance_width * max_line_length * 3;
    };

    const stride = width * 4;
    const size = stride * height;

    const fd = try posix.memfd_create("zig-prompt", 0);
    try posix.ftruncate(fd, size);
    const screen = try posix.mmap(
        null,
        size,
        posix.PROT.READ | posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    return .{
        .fd = fd,
        .screen = screen,
        .height = height,
        .width = width,
    };
}

pub fn deinit(self: *DrawContext) void {
    self.font_face.deinit();
    self.freetype_lib.deinit();
}

pub fn draw_window(self: *const DrawContext, screen: *const ScreenBuffer) !void {
    const width = screen.width;
    const height = screen.height;
    const background_color = self.config.background_color;
    const border_color = self.config.border_color;
    const border_size = self.config.border_size;

    // Draw background
    for (0..height) |y| {
        const row = screen.screen[width * y * 4 ..];
        var color = background_color;

        if (y < border_size or y >= height - border_size) {
            color = border_color;
        }

        for (0..width) |x| {
            @as(*u32, @alignCast(@ptrCast(row[x * 4 ..][0..4].ptr))).* = color: {
                if (x < border_size or x >= width - border_size)
                    break :color @bitCast(border_color);
                break :color @bitCast(color);
            };
        }
    }

    // Draw text

    const pixel_height = self.config.font_size * 3;
    // TODO: Make this actually follow font point size
    try self.font_face.setPixelSizes(pixel_height, 0);

    var origin = Vector{ .x = 10, .y = pixel_height };

    for (self.config.options) |option| {
        defer origin.x = 10;
        defer origin.y += pixel_height;
        const lines: [3][]const u8 = .{ option.key, self.config.seperator, option.desc };
        for (lines) |line| {
            for (line) |char| {
                const glyph_index = self.font_face.getCharIndex(char) orelse 0;

                try self.font_face.loadGlyph(glyph_index, .{
                    .bitmap_metrics_only = true,
                    .render = true,
                    .target_normal = true,
                });

                const glyph_slot = self.font_face.glyph();

                const metrics = glyph_slot.metrics();
                var glyph = try glyph_slot.getGlyph();
                const bitmap_glyph = try glyph.toBitmapGlyph(.normal, .{ .x = @intCast(origin.x), .y = @intCast(origin.y) });
                const bitmap = bitmap_glyph.bitmap();

                const offset_x = bitmap_glyph.left();
                const offset_y = bitmap_glyph.top();
                log.debug("{c} :: offset x: {}, offset y: {}", .{ char, offset_x, offset_y });

                const glyph_origin = Vector{
                    .x = @intCast(@as(isize, @intCast(origin.x)) + offset_x),
                    .y = @intCast(@as(isize, @intCast(origin.y)) - offset_y),
                };

                log.debug("glyph origin x: {}, y: {}", glyph_origin);
                try draw_bitmap(self, screen, &bitmap, glyph_origin);

                const advance_x = metrics.horiAdvance >> 6;

                log.debug("origin x: {}, y: {}", origin);
                log.debug("advance x: {}", .{advance_x});
                origin.x = @intCast(@as(isize, @intCast(origin.x)) + advance_x);
            }
        }
    }
}

pub fn draw_bitmap(ctx: *const DrawContext, screen: *const ScreenBuffer, bitmap: *const freetype.Bitmap, origin: Vector) !void {
    const screen_width = screen.width;
    const screen_height = screen.height;
    const screen_stride = screen.width * 4;

    const bitmap_stride = @as(usize, @intCast(bitmap.pitch()));
    const bitmap_width = bitmap.width();
    const bitmap_height = bitmap.rows();

    log.debug("bitmap height: {}, width: {}", .{ bitmap_height, bitmap_width });
    assert(bitmap_width + origin.x <= screen_width);
    assert(bitmap_height + origin.y <= screen_height);

    if (bitmap.buffer()) |buffer| {
        for (0..bitmap_height) |y| {
            const screen_row_forwards = screen.screen[(origin.y + y) * screen_stride ..];
            const screen_row = screen_row_forwards[origin.x * 4 ..][0 .. bitmap_stride * 4];

            @memcpy(screen_row[0..4], std.mem.asBytes(&ctx.config.text_color));

            const buffer_row = buffer[y * bitmap_stride ..][0..bitmap_stride];

            for (buffer_row, 0..) |alpha, idx| {
                var text_color = ctx.config.text_color;
                text_color.a = alpha;
                const color = colors.composite(ctx.config.background_color, text_color);
                @memcpy(screen_row[idx * 4 ..][0..4], std.mem.asBytes(&color));
            }
        }
    }
}

const assets = @import("assets");

const Config = @import("config.zig").Config;
const colors = @import("colors.zig");
const Color = colors.Color;

const freetype = @import("freetype");

const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const assert = std.debug.assert;
const log = std.log.scoped(.DrawContext);
