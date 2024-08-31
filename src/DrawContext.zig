const Vector = struct {
    x: u31,
    y: u31,
};

pub const ScreenBuffer = struct {
    fd: std.posix.fd_t,
    screen: []u32,
    height: u31,
    width: u31,
};

pub const DrawContext = @This();

config: *const Config,
freetype_lib: freetype.FT_Library,
font_face: freetype.FT_Face,

allocator: Allocator,
freetype_allocator: freetype.FT_MemoryRec_,

alloc_user: AllocUser,

const AllocUser = struct {
    allocator: Allocator,
    alloc_list: AllocList,

    const AllocList = ArrayListUnmanaged([]u8);
};

pub fn init(allocator: Allocator, config: *const Config) !*DrawContext {
    var ctx = try allocator.create(DrawContext);
    errdefer allocator.destroy(ctx);
    ctx.config = config;
    ctx.allocator = allocator;

    ctx.alloc_user = AllocUser{
        .allocator = allocator,
        .alloc_list = try AllocUser.AllocList.initCapacity(allocator, 64),
    };

    ctx.freetype_allocator = freetype.FT_MemoryRec_{
        .user = &ctx.alloc_user,
        .alloc = freetype_alloc,
        .free = freetype_free,
        .realloc = freetype_realloc,
    };

    //var err = freetype.FT_Init_FreeType(&ctx.freetype_lib);
    //errdefer freetype.FT_Done_FreeType(&ctx.freetype_lib);

    var err = freetype.FT_New_Library(&ctx.freetype_allocator, &ctx.freetype_lib);
    errdefer freetype.FT_Done_Library(&ctx.freetype_lib);
    if (err != 0) @panic("failed to initilize freetype");

    freetype.FT_Add_Default_Modules(ctx.freetype_lib);
    freetype.FT_Set_Default_Properties(ctx.freetype_lib);

    log.info("freetype version: {}.{}.{}", .{ freetype.FREETYPE_MAJOR, freetype.FREETYPE_MINOR, freetype.FREETYPE_PATCH });

    // TODO: allow for custom font
    err = freetype.FT_New_Memory_Face(ctx.freetype_lib, options.font_data.ptr, options.font_data.len, 0, &ctx.font_face);
    errdefer freetype.FT_Done_Face(&ctx.font_face);
    if (err != 0) @panic("failed to initilize font");

    const font_family = if (ctx.font_face.*.family_name) |family| mem.span(@as([*:0]const u8, @ptrCast(family))) else "none";
    const font_style = if (ctx.font_face.*.style_name) |style| mem.span(@as([*:0]const u8, @ptrCast(style))) else "none";

    assert(ctx.font_face.*.face_flags & freetype.FT_FACE_FLAG_HORIZONTAL != 0); // make sure it has horizontal spacing metrics

    log.info("font family: {s}, style: {s}", .{ font_family, font_style });

    err = freetype.FT_Set_Pixel_Sizes(ctx.font_face, config.font_size * 3, 0);
    if (err != 0) @panic("failed to initilize font");

    return ctx;
}

pub fn deinit(self: *DrawContext) void {
    _ = freetype.FT_Done_Face(self.font_face);
    _ = freetype.FT_Done_Library(self.freetype_lib);

    for (self.alloc_user.alloc_list.items) |allocation| {
        log.warn("FreeType failed to deallocate {} bytes at 0x{x}", .{ allocation.len, @intFromPtr(allocation.ptr) });
        if (options.freetype_allocator == .default)
            std.c.free(allocation.ptr)
        else
            self.alloc_user.allocator.free(allocation);
    }

    self.alloc_user.alloc_list.deinit(self.allocator);

    // is it safe to free yourself like this?
    self.allocator.destroy(self);
}

pub fn createScreenBuffer(self: *const DrawContext) !ScreenBuffer {
    const bbox = self.font_face.*.bbox;
    const height = self.config.height orelse height: {
        const font_height: u31 = @as(u31, @intCast((bbox.yMax - bbox.yMin) >> 6));
        const font_lines: u31 = @intCast(self.config.options.len);

        break :height font_height * font_lines * 11 / 10;
    };
    const width = self.config.width orelse width: {
        const font_advance_width: u31 = @as(u31, @intCast(self.font_face.*.max_advance_width >> 6));
        var max_line_length: u31 = 0;
        for (self.config.options) |option| {
            const line_len: u31 = @intCast(option.key.len + option.desc.len);
            max_line_length = @intCast(@max(max_line_length, line_len));
        }
        max_line_length += @intCast(self.config.seperator.len);

        break :width font_advance_width * max_line_length * 3;
    };

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
    log.info("drawing window", .{});
    const width = screen.width;
    const height = screen.height;
    const background_color = self.config.background_color;
    const border_color = self.config.border_color;
    const border_size = self.config.border_size;

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

    const pixel_height = self.config.font_size * 3;

    var origin = Vector{ .x = 10, .y = pixel_height };

    var err: i64 = undefined;

    for (self.config.options) |option| {
        const lines: [3][]const u8 = .{ option.key, self.config.seperator, option.desc };
        for (lines) |line| {
            for (line) |char| {
                log.info("loading char '{c}'", .{char});
                err = freetype.FT_Load_Char(self.font_face, char, freetype.FT_LOAD_RENDER);
                if (err != 0) @panic("Failed to load char '" ++ .{char} ++ "'");

                const glyph_slot = self.font_face.*.glyph;

                const bitmap_left: u31 = @intCast(glyph_slot.*.bitmap_left);
                const bitmap_top: u31 = @intCast(glyph_slot.*.bitmap_top);

                const glyph_origin = Vector{
                    .x = origin.x + bitmap_left,
                    .y = origin.y - bitmap_top,
                };

                draw_bitmap(self, screen, glyph_slot.*.bitmap, glyph_origin);

                origin.x += @intCast(glyph_slot.*.advance.x >> 6);
                origin.y += @intCast(glyph_slot.*.advance.y >> 6);
            }
        }
    }
}

pub fn draw_bitmap(ctx: *const DrawContext, screen: *const ScreenBuffer, bitmap: freetype.FT_Bitmap, origin: Vector) void {
    const screen_width = screen.width;
    const screen_height = screen.height;
    const screen_stride = screen_width;

    const bitmap_width = bitmap.width;
    const bitmap_height = bitmap.rows;

    log.debug("bitmap width: {}, height: {}", .{ bitmap_width, bitmap_height });

    if (bitmap_width == 0 or bitmap_height == 0) return;

    log.debug("origin x: {}, y: {}", origin);
    log.debug("bitmap height: {}, width: {}", .{ bitmap_height, bitmap_width });
    assert(bitmap_width + origin.x <= screen_width);
    assert(bitmap_height + origin.y <= screen_height);

    if (bitmap.buffer) |bitmap_buffer| {
        for (0..bitmap_height) |y| {
            const screen_row_forwards = screen.screen[(origin.y + y) * screen_stride ..];
            const screen_row = screen_row_forwards[origin.x..][0..bitmap_width];

            screen_row[0] = @bitCast(ctx.config.text_color);

            const bitmap_row = bitmap_buffer[y * bitmap_width ..][0..bitmap_width];

            for (bitmap_row, 0..) |alpha, idx| {
                var text_color = ctx.config.text_color;
                text_color.a = alpha;
                const color = colors.composite(ctx.config.background_color, text_color);

                screen_row[idx] = @bitCast(color);
            }
        }
    } else {
        log.warn("Character has a non-zero size and no bitmap buffer!", .{});
    }
}

const FT_Memory = freetype.FT_Memory;

fn freetype_alloc(memory: FT_Memory, _size: c_long) callconv(.C) ?*anyopaque {
    assert(_size > 0);
    assert(memory != null);
    assert(memory.*.user != null);

    const size: usize = @intCast(_size);

    const user = @as(*AllocUser, @alignCast(@ptrCast(memory.*.user)));

    const new = if (options.freetype_allocator == .default)
        @as([*]u8, @ptrCast(std.c.malloc(size)))[0..size]
    else
        user.allocator.alloc(u8, size) catch @panic("OOM");

    user.alloc_list.append(user.allocator, new) catch @panic("OOM");

    return new.ptr;
}

fn freetype_free(memory: FT_Memory, ptr: ?*anyopaque) callconv(.C) void {
    assert(ptr != null);
    assert(memory != null);
    assert(memory.*.user != null);

    const user = @as(*AllocUser, @alignCast(@ptrCast(memory.*.user)));

    const allocation, const idx = allocation: {
        for (user.alloc_list.items, 0..) |allocation, idx| {
            if (ptr == @as(?*anyopaque, allocation.ptr)) break :allocation .{ allocation, idx };
        }
        @panic("FreeType freed an unowned pointer");
    };

    switch (options.freetype_allocator) {
        .default => std.c.free(allocation.ptr),
        .custom => user.allocator.free(allocation),
    }

    _ = user.alloc_list.swapRemove(idx);
}

fn freetype_realloc(memory: FT_Memory, _cur_size: c_long, _new_size: c_long, ptr: ?*anyopaque) callconv(.C) ?*anyopaque {
    //log.debug("freetype realloc ptr: {*}, len before: {}, after: {}", .{ ptr, _cur_size, _new_size });

    assert(ptr != null);
    assert(_cur_size > 0);
    assert(_new_size > 0);
    assert(memory != null);
    assert(memory.*.user != null);

    const cur_size: usize = @intCast(_cur_size);
    const new_size: usize = @intCast(_new_size);

    if (cur_size == new_size) return ptr;

    const user = @as(*AllocUser, @alignCast(@ptrCast(memory.*.user)));

    const allocation, const idx = allocation: {
        for (user.alloc_list.items, 0..) |allocation, idx| {
            if (ptr == @as(?*anyopaque, allocation.ptr)) break :allocation .{ allocation, idx };
        }
        @panic("FreeType freed an unowned pointer");
    };

    assert(cur_size == allocation.len);

    const new = if (options.freetype_allocator == .default)
        @as([*]u8, @ptrCast(std.c.realloc(ptr, new_size)))[0..new_size]
    else
        user.allocator.realloc(allocation, new_size) catch @panic("OOM");

    user.alloc_list.items[idx] = new;

    const result_ptr = @as(?*anyopaque, @ptrCast(new.ptr));

    return result_ptr;
}

test "freetype allocator" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;

    var alloc_user = AllocUser{
        .allocator = allocator,
        .alloc_list = try ArrayListUnmanaged([]u8).initCapacity(allocator, 50),
    };
    defer alloc_user.alloc_list.deinit(allocator);

    var freetype_allocator = freetype.FT_MemoryRec_{
        .user = &alloc_user,
        .alloc = freetype_alloc,
        .free = freetype_free,
        .realloc = freetype_realloc,
    };

    var freetype_lib: freetype.FT_Library = undefined;

    var err = freetype.FT_New_Library(&freetype_allocator, &freetype_lib);
    defer _ = freetype.FT_Done_Library(freetype_lib);
    try expect(err == 0);

    freetype.FT_Add_Default_Modules(freetype_lib);

    log.info("freetype version: {}.{}.{}", .{ freetype.FREETYPE_MAJOR, freetype.FREETYPE_MINOR, freetype.FREETYPE_PATCH });

    var font_face: freetype.FT_Face = undefined;

    err = freetype.FT_New_Memory_Face(freetype_lib, options.font_data.ptr, options.font_data.len, 0, &font_face);
    defer _ = freetype.FT_Done_Face(font_face);
    try expect(err == 0);

    err = freetype.FT_Set_Pixel_Sizes(font_face, 15, 0);
    try expect(err == 0);

    for ("testing -> test\n") |char| {
        err = freetype.FT_Load_Char(font_face, char, freetype.FT_LOAD_RENDER);
        try expect(err == 0);
    }
}

test "init" {
    //pub fn init(parent_allocator: Allocator, config: *const Config) !*DrawContext {
    const context = try init(std.testing.allocator, &Config{
        .arena = ArenaAllocator.init(std.testing.allocator),

        .program_name = "test",
        .font_size = 20,

        .width = 100,
        .height = 100,

        .title = "test",

        .background_color = colors.main,
        .text_color = colors.text,

        .border_size = 3,
        .border_color = colors.iris,

        .options = &[1]config_mod.Option{.{ .key = "a", .desc = "b" }},
        .seperator = " ",
    });
    defer context.deinit();

    const screen_buffer = try context.createScreenBuffer();

    try context.draw_window(&screen_buffer);
}

const options = @import("options");

const config_mod = @import("config.zig");
const Config = config_mod.Config;
const colors = @import("colors.zig");
const Color = colors.Color;

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
const ArenaAllocator = std.heap.ArenaAllocator;
const LoggingAllocator = std.heap.ScopedLoggingAllocator(.DrawContext, .debug, .err);
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const assert = std.debug.assert;
const log = std.log.scoped(.DrawContext);
