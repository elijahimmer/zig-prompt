const Vector = struct {
    x: u31,
    y: u31,
};

/// Need to call `close` when done with
/// The screen in this buffer is the colors on the screen, where each element is one pixel's colors.
pub const ScreenBuffer = struct {
    fd: std.posix.fd_t,
    screen: []u32,
    height: u31,
    width: u31,

    pub fn deinit(self: *const @This()) void {
        posix.close(self.fd);
    }
};

pub const TextInfo = struct {
    max_key_width: u32,
    separator_width: u32,
    max_desc_width: u32,
};

pub const DrawContext = @This();

config: *const Config,
text_info: TextInfo,

freetype_lib: freetype.FT_Library,
font_face: freetype.FT_Face,

freetype_allocator: freetype.FT_MemoryRec_,

parent_allocator: Allocator,
alloc_user: freetype_utils.AllocUser,

pub fn init(parent_allocator: Allocator, output_context: *const OutputContext, config: *const Config) !*DrawContext {
    var ctx = try parent_allocator.create(DrawContext);
    ctx.* = undefined;

    errdefer parent_allocator.destroy(ctx);
    ctx.config = config;
    ctx.parent_allocator = parent_allocator;

    const alloc = alloc: {
        const alloc = switch (options.freetype_allocator) {
            .c => std.heap.c_allocator,
            .zig => parent_allocator,
        };

        break :alloc alloc;
    };

    ctx.alloc_user = try freetype_utils.AllocUser.init(alloc);
    ctx.freetype_allocator = freetype.FT_MemoryRec_{
        .user = &ctx.alloc_user,
        .alloc = freetype_utils.alloc,
        .free = freetype_utils.free,
        .realloc = freetype_utils.realloc,
    };

    // // standard setup without a custom allocator
    //var err = freetype.FT_Init_FreeType(&ctx.freetype_lib);
    //errdefer freetype.FT_Done_FreeType(&ctx.freetype_lib);

    {
        const err = freetype.FT_New_Library(&ctx.freetype_allocator, &ctx.freetype_lib);
        freetype_utils.errorAssert(err, "Failed to initilize freetype");
    }
    errdefer freetype.FT_Done_Library(&ctx.freetype_lib);

    // TODO: Maybe customize modules to only what is needed.
    freetype.FT_Add_Default_Modules(ctx.freetype_lib);
    freetype.FT_Set_Default_Properties(ctx.freetype_lib);

    log.info("freetype version: {}.{}.{}", .{ freetype.FREETYPE_MAJOR, freetype.FREETYPE_MINOR, freetype.FREETYPE_PATCH });

    // TODO: allow for runtime custom font
    {
        const font_data = options.font_data;
        const err = freetype.FT_New_Memory_Face(ctx.freetype_lib, font_data.ptr, font_data.len, 0, &ctx.font_face);
        freetype_utils.errorAssert(err, "Failed to initilize font");
    }
    errdefer freetype.FT_Done_Face(&ctx.font_face);

    const font_family = if (ctx.font_face.*.family_name) |family| mem.span(@as([*:0]const u8, @ptrCast(family))) else "none";
    const font_style = if (ctx.font_face.*.style_name) |style| mem.span(@as([*:0]const u8, @ptrCast(style))) else "none";

    assert(ctx.font_face.*.face_flags & freetype.FT_FACE_FLAG_HORIZONTAL != 0); // make sure it has horizontal spacing metrics

    log.info("font family: {s}, style: {s}", .{ font_family, font_style });

    { // set font encoding
        const err = freetype.FT_Select_Charmap(ctx.font_face, freetype.FT_ENCODING_UNICODE);
        freetype_utils.errorAssert(err, "Failed to set charmap to unicode");
    }

    { // set font size
        // screen size in milimeters
        const physical_height = output_context.physical_height;
        const physical_width = output_context.physical_width;

        // screen pixel size
        const height = output_context.height;
        const width = output_context.width;

        // mm to inches, (mm * 5) / 127
        const horz_dpi = if (physical_height != null and height != null and height.? > 0)
            (@as(u64, @intCast(height.?)) * 127) / (@as(u64, @intCast(physical_height.?)) * 5)
        else
            0;

        const vert_dpi = if (physical_width != null and width != null and width.? > 0)
            (@as(u64, @intCast(width.?)) * 127) / (@as(u64, @intCast(physical_width.?)) * 5)
        else
            0;

        const err = freetype.FT_Set_Char_Size(
            ctx.font_face,
            @intCast(config.font_size << 6), // multiply by 64 because they measure it in 1/64 points
            0,
            @intCast(horz_dpi),
            @intCast(vert_dpi),
        );
        freetype_utils.errorAssert(err, "Failed to set font size");
    }

    ctx.text_info = try getTextInfo(ctx.font_face, config);

    return ctx;
}

pub fn deinit(self: *DrawContext) void {
    {
        const err = freetype.FT_Done_Face(self.font_face);
        freetype_utils.errorPrint("Failed to free FreeType Font: '{s}'", err, .{});
    }
    {
        const err = freetype.FT_Done_Library(self.freetype_lib);
        freetype_utils.errorPrint("Failed to free FreeType Library: '{s}'", err, .{});
    }

    for (self.alloc_user.alloc_list.items) |allocation| {
        log.warn("FreeType failed to deallocate {} bytes at 0x{x}", .{ allocation.len, @intFromPtr(allocation.ptr) });
        self.alloc_user.allocator.free(allocation);
    }

    self.alloc_user.alloc_list.deinit(self.alloc_user.allocator);

    // is it safe to free yourself like this?
    self.parent_allocator.destroy(self);
}

pub fn getTextInfo(font_face: freetype.FT_Face, config: *const Config) !TextInfo {
    var text_info = TextInfo{
        .max_key_width = 0,
        .separator_width = 0,
        .max_desc_width = 0,
    };

    log.debug("=== Get Text Info", .{});

    for (config.options) |option| {
        const sections: [3][]const u8 = .{ option.key, config.separator, option.desc };
        const info_spaces: [3]*u32 = .{ &text_info.max_key_width, &text_info.separator_width, &text_info.max_desc_width };
        for (sections, info_spaces) |section, info| {
            var total_size: u31 = 0;

            var utf8_iter = unicode.Utf8Iterator{ .bytes = section, .i = 0 };

            while (utf8_iter.nextCodepointSlice()) |char_slice| {
                log.debug("Measuring character '{s}'", .{char_slice});
                const char = unicode.utf8Decode(char_slice) catch char: {
                    log.warn("\tFailed to utf8 decode char.", .{});
                    break :char 0;
                };

                const char_idx = freetype.FT_Get_Char_Index(font_face, char);
                if (char_idx == 0) log.warn("\tChar is unknown, or not in font.", .{});

                {
                    const err = freetype.FT_Load_Glyph(font_face, char_idx, freetype.FT_LOAD_DEFAULT);

                    if (freetype_utils.isErr(err)) {
                        freetype_utils.errorPrint("Failed to load Glyph with : {s}", err, .{});

                        const err2 = freetype.FT_Load_Glyph(font_face, 0, freetype.FT_LOAD_DEFAULT);
                        freetype_utils.errorAssert(err2, "Failed to load replacement glyph!");
                    }
                }

                const glyph_slot = font_face.*.glyph;

                log.debug("\tmetrics x: {}, y: {}", .{ glyph_slot.*.metrics.width, glyph_slot.*.metrics.height });

                total_size += @intCast(glyph_slot.*.metrics.horiAdvance);
            }

            info.* = @max(info.*, total_size);
        }
    }

    log.debug("text info key: {}, sep: {}, desc: {}", text_info);

    return text_info;
}

/// caller takes ownership of ScreenBuffer, and must close it when done.
pub fn createScreenBuffer(self: *const DrawContext) !ScreenBuffer {
    const height = @max(self.config.height orelse 0, height: {
        const font_height: u31 = @intCast(self.font_face.*.height >> 6);
        const should_round_up = (font_height << 6) < self.font_face.*.height;

        const font_lines: u31 = @intCast(self.config.options.len);

        break :height (font_height + @intFromBool(should_round_up)) * font_lines + (self.config.border_size * 2) + self.config.padding_top + self.config.padding_bottom;
    });

    const width = @max(self.config.width orelse 0, width: {
        const ti = &self.text_info;
        const text_width: u31 = @intCast((ti.max_key_width + ti.separator_width + ti.max_desc_width));

        const should_round_up = ((text_width >> 6) << 6) < text_width;

        break :width (text_width >> 6) + @intFromBool(should_round_up) + (self.config.border_size * 2) + self.config.padding_left + self.config.padding_right;
    });

    // stride in u8
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

    // convert it from a u8 array into a u32 array, so each color is one element
    var screen_adjusted: []u32 = undefined;
    screen_adjusted.ptr = @ptrCast(screen.ptr);
    screen_adjusted.len = height * width;

    // stride is width from here on in
    return .{
        .fd = fd,
        .screen = screen_adjusted,
        .height = height,
        .width = width,
    };
}

pub fn draw_window(self: *const DrawContext, screen: *const ScreenBuffer) !void {
    log.info("=== Drawing Window", .{});
    const width = screen.width;
    const height = screen.height;
    const border_size = self.config.border_size;
    const background_color = self.config.background_color;
    const border_color = self.config.border_color;

    // Draw background
    for (0..height) |y| {
        const row = screen.screen[width * y ..];
        const color = if (y < border_size or y >= height - border_size)
            border_color
        else
            background_color;

        for (0..width) |x| {
            row[x] = if (x < border_size or x >= width - border_size)
                @bitCast(border_color)
            else
                @bitCast(color);
        }
    }

    // Draw text

    const separator_width = self.text_info.separator_width;
    const key_width = self.text_info.max_key_width;
    const desc_width = self.text_info.max_desc_width;

    // border_size << 7 because * 64 for 26.6 frac pixels, then * 2 bc one on each side
    assert(key_width + separator_width + desc_width + (border_size << 7) <= width << 6);

    const separator_x = (@as(u31, border_size) << 6) + key_width + (self.config.padding_left << 6);

    var pen_y = (@as(u31, border_size) << 6) + @as(u31, @intCast(self.font_face.*.ascender)) + (self.config.padding_top << 6);

    for (self.config.options) |option| {
        assert(pen_y < height << 6);

        defer pen_y += @intCast(self.font_face.*.max_advance_height);

        var pen_x: u31 = @intCast(separator_x);

        // draw key
        {
            // TODO: Make this support unicode
            var reverse_iter = mem.reverseIterator(option.key);
            while (reverse_iter.next()) |char| {
                log.debug("loading char '{c}'", .{char});
                log.debug("\tChar code : 0x{x}", .{char});
                {
                    const err = freetype.FT_Load_Char(self.font_face, char, freetype.FT_LOAD_RENDER);
                    freetype_utils.errorAssert(err, "Failed to load char '" ++ .{char} ++ "'");
                }

                const glyph_slot = self.font_face.*.glyph;

                assert(glyph_slot.*.bitmap_left >= 0);
                assert(glyph_slot.*.bitmap_top >= 0);

                const bitmap_left: u31 = @intCast(glyph_slot.*.bitmap_left);
                const bitmap_top: u31 = @intCast(glyph_slot.*.bitmap_top);

                const adv_x: u31 = @intCast(glyph_slot.*.advance.x);

                assert(pen_x > adv_x);
                pen_x -= adv_x;

                //assert(origin.x + bitmap_left < width);
                assert(pen_y - bitmap_top + glyph_slot.*.bitmap.rows < (height << 6));
                const glyph_origin = Vector{
                    .x = (pen_x >> 6) + bitmap_left, // add bitmap_left, because my origin is top left of bm, theirs is draw line
                    .y = (pen_y >> 6) - bitmap_top,
                };

                draw_bitmap(self, screen, glyph_slot.*.bitmap, glyph_origin, self.config.key_color);
            }
        }

        // draw separator
        pen_x = @intCast(separator_x);

        const sections: [2][]const u8 = .{ self.config.separator, option.desc };
        const color_list: [2]Color = .{ self.config.separator_color, self.config.desc_color };

        for (sections, color_list) |section, color| {
            var utf8_iter = unicode.Utf8Iterator{ .bytes = section, .i = 0 };
            while (utf8_iter.nextCodepointSlice()) |char_slice| {
                log.debug("loading char '{s}'", .{char_slice});

                assert(pen_x < width << 6);

                const utf8_char = if (char_slice.len == 1) char_slice[0] else utf8_char: {
                    break :utf8_char unicode.utf8Decode(char_slice) catch |err| {
                        log.warn("\tFailed to decode character as UTF8 with: {s}", .{@errorName(err)});

                        break :utf8_char 0;
                    };
                };

                // direct copy bytes into cint
                //const utf8_char: u32 = utf8_char: {
                //    var utf8_char: u32 = 0;
                //    const utf8_char_bytes = mem.asBytes(&utf8_char);

                //    @memcpy(utf8_char_bytes[4 - char_slice.len ..], char_slice);

                //    mem.reverse(u8, utf8_char_bytes);

                //    break :utf8_char utf8_char;
                //};
                log.debug("\tChar code : 0x{x}", .{utf8_char});

                {
                    const err = freetype.FT_Load_Char(self.font_face, utf8_char, freetype.FT_LOAD_RENDER);
                    freetype_utils.errorAssert(err, "Failed to load char");
                }

                //log.debug("\tchar_idx: 0x{x}", .{char_idx});

                //{
                //    const err = freetype.FT_Render_Glyph(self.font_face.*.glyph, freetype.FT_RENDER_MODE_NORMAL);

                //    freetype_utils.errorAssert(err, "Failed to render glyph!");
                //}

                const glyph_slot = self.font_face.*.glyph;

                assert(glyph_slot.*.bitmap_left >= 0);
                assert(glyph_slot.*.bitmap_top >= 0);

                const bitmap_left: u31 = @intCast(glyph_slot.*.bitmap_left);
                const bitmap_top: u31 = @intCast(glyph_slot.*.bitmap_top);

                //assert(origin.x + bitmap_left < width);
                assert(pen_y - bitmap_top + glyph_slot.*.bitmap.rows < (height << 6));
                const glyph_origin = Vector{
                    .x = (pen_x >> 6) + bitmap_left, // add bitmap_left, because the origin is not the start of the glyph, but the main start line
                    .y = (pen_y >> 6) - bitmap_top,
                };

                draw_bitmap(self, screen, glyph_slot.*.bitmap, glyph_origin, color);

                pen_x += @intCast(glyph_slot.*.advance.x);
            }
        }
    }
}

pub fn draw_bitmap(ctx: *const DrawContext, screen: *const ScreenBuffer, bitmap: freetype.FT_Bitmap, origin: Vector, color: Color) void {
    const screen_width = screen.width;
    const screen_height = screen.height;

    const bitmap_width = bitmap.width;
    const bitmap_height = bitmap.rows;

    log.debug("\tbitmap width: {}, height: {}", .{ bitmap_width, bitmap_height });

    // zero size char (whitespace likely)
    if (bitmap_width == 0 or bitmap_height == 0) return;

    log.debug("\torigin x: {}, y: {}", origin);
    assert(bitmap_width + origin.x < screen_width);
    assert(bitmap_height + origin.y < screen_height);

    if (bitmap.buffer == null) {
        log.warn("\tCharacter has a non-zero size and no bitmap buffer!", .{});
        return;
    }

    const bitmap_buffer = bitmap.buffer.?;

    for (0..bitmap_height) |y| {
        const screen_row_forwards = screen.screen[(origin.y + y) * screen_width ..];
        const screen_row = screen_row_forwards[origin.x..][0..bitmap_width];

        //screen_row[0] = @bitCast(ctx.config.text_color);

        const bitmap_row = bitmap_buffer[y * bitmap_width ..][0..bitmap_width];

        for (bitmap_row, 0..) |alpha, idx| {
            var text_color = color;
            text_color.a = alpha;
            const draw_color = colors.composite(ctx.config.background_color, text_color);

            screen_row[idx] = @bitCast(draw_color);
        }
    }
}

test "init" {
    const config = Config{
        .arena = undefined,

        .program_name = "test",
        .font_size = 20,

        .width = 100,
        .height = 100,

        .title = "test",

        .background_color = all_colors.main,
        .key_color = all_colors.text,
        .separator_color = all_colors.text,
        .desc_color = all_colors.text,

        .padding_top = 0,
        .padding_left = 0,
        .padding_right = 0,
        .padding_bottom = 0,

        .border_size = 3,
        .border_color = all_colors.iris,

        .options = &[1]config_mod.Option{.{ .key = "a", .desc = "b" }},
        .separator = " ",
    };

    const context = try init(std.testing.allocator, &.{}, &config);
    defer context.deinit();

    assert(context.text_info.max_key_width > 0);
    assert(context.text_info.separator_width > 0);
    assert(context.text_info.max_desc_width > 0);

    const screen_buffer = try context.createScreenBuffer();
    defer screen_buffer.deinit();

    try context.draw_window(&screen_buffer);
}

const freetype_utils = @import("freetype.zig");

const options = @import("options");

const config_mod = @import("config.zig");
const Config = config_mod.Config;

const colors = @import("colors.zig");
const all_colors = colors.all_colors;
const Color = colors.Color;

const OutputContext = @import("main.zig").OutputContext;

const freetype = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftsystem.h");
    @cInclude("freetype/ftmodapi.h");
});

const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const assert = std.debug.assert;
const panic = std.debug.panic;
const log = std.log.scoped(.DrawContext);
const unicode = std.unicode;
