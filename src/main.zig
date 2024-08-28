pub fn main() anyerror!void {
    const config = try config_parse_argv(std.heap.page_allocator);

    const freetype_lib = try freetype.Library.init();
    defer freetype_lib.deinit();

    log.info("freetype version: {}.{}.{}", freetype_lib.version());

    const font_face = try freetype_lib.createFaceMemory(assets.font_data, 0);
    defer font_face.deinit();

    log.info("font family: {s}, style: {s}", .{ font_face.familyName() orelse "none", font_face.styleName() orelse "none" });

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var context = Context{
        .shm = null,
        .compositor = null,
        .output = null,
        .wm_base = null,
        .layer_shell = null,
    };

    registry.setListener(*Context, registryListener, &context);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const shm = context.shm orelse return error.@"No Wayland Shared Memory";
    const compositor = context.compositor orelse return error.@"No Wayland Compositor";
    //const output = context.output orelse return error.@"No Wayland Output";
    //const wm_base = context.wm_base orelse return error.@"No Xdg Window Manager Base";
    const layer_shell = context.layer_shell orelse return error.@"No WlRoots Layer Shell";

    const buffer = buffer: {
        const stride = config.width * 4;
        const size = stride * config.height;

        const fd = try posix.memfd_create("wayprompt", 0);
        try posix.ftruncate(fd, size);
        const data = try posix.mmap(
            null,
            size,
            posix.PROT.READ | posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );

        try draw_window(data, &config, &freetype_lib, &font_face);

        const pool = try shm.createPool(fd, size);
        defer pool.destroy();

        break :buffer try pool.createBuffer(0, config.width, config.height, stride, wl.Shm.Format.argb8888);
    };
    defer buffer.destroy();

    const surface = try compositor.createSurface();
    defer surface.destroy();

    const layer_surface = try layer_shell.getLayerSurface(surface, null, zwlr.LayerShellV1.Layer.top, "elijah-immer/wayprompt");
    defer layer_surface.destroy();

    layer_surface.setSize(config.width, config.height);
    layer_surface.setKeyboardInteractivity(zwlr.LayerSurfaceV1.KeyboardInteractivity.none);

    var running = true;

    layer_surface.setListener(*bool, layerSurfaceListener, &running);

    surface.commit();
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    surface.attach(buffer, 0, 0);
    surface.commit();

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    while (running) {
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
}

fn draw_window(data: []u8, config: *const Config, freetype_lib: *const freetype.Library, font_face: *const freetype.Face) !void {
    // draw background
    for (0..config.height) |y| {
        var row = data[config.width * y * 4 ..];
        const color = color: {
            if (y < config.border_width or y >= config.height - config.border_width)
                break :color config.border_color;
            break :color config.background_color;
        };
        for (0..config.width) |x| {
            @memcpy(row[x * 4 ..][0..4], mem.asBytes(&color: {
                if (x < config.border_width or x >= config.width - config.border_width)
                    break :color config.border_color;
                break :color color;
            }));
        }
    }

    // draw text
    try font_face.setCharSize(config.font_size * 64, 0, @as(u16, @intCast(config.width)), @as(u16, @intCast(config.height)));

    var origin = Vector{ .x = 10, .y = 10 };

    for (config.text) |char| {
        const glyph_index = font_face.getCharIndex(char) orelse 0;

        try font_face.loadGlyph(glyph_index, .{
            .bitmap_metrics_only = true,
            .render = true,
            .target_normal = true,
        });

        const glyph_slot = font_face.glyph();
        try glyph_slot.render(.normal);

        var bitmap = glyph_slot.bitmap();
        defer bitmap.deinit(freetype_lib.*);

        try draw_bitmap(data, config, &bitmap, origin);

        const glyph = try glyph_slot.getGlyph();

        log.debug("origin x: {}, y: {}", origin);
        origin.x = @as(usize, @intCast(@as(isize, @intCast(origin.x)) + glyph.advanceX()));
        origin.y = @as(usize, @intCast(@as(isize, @intCast(origin.y)) + glyph.advanceY()));
        log.debug("origin x: {}, y: {}", origin);
    }
}

const Vector = struct {
    x: usize,
    y: usize,
};

fn draw_bitmap(data: []u8, config: *const Config, bitmap: *const freetype.Bitmap, origin: Vector) !void {
    const data_width = config.width;
    const data_height = config.height;
    const data_stride = data_width * 4;

    const bitmap_stride = bitmap.width();
    const bitmap_width = bitmap_stride / 4;
    const bitmap_height = bitmap.rows();

    assert(bitmap_width <= data_width);
    assert(bitmap_height <= data_height);

    log.debug("bitmap height: {}, width: {}", .{ bitmap_height, bitmap_width });

    if (bitmap.buffer()) |buffer| {
        for (0..bitmap_height) |y| {
            const data_row_forwards = data[(origin.y + y) * data_stride ..];
            const data_row = data_row_forwards[origin.x * 4 ..][0 .. bitmap_stride * 4];

            const buffer_row = buffer[y * bitmap_stride ..][0..bitmap_stride];

            for (buffer_row, 0..) |alpha, idx| {
                var text_color = config.text_color;
                text_color.a = alpha;
                const color = colors.composite(config.background_color, text_color);
                @memcpy(data_row[idx * 4 ..][0..4], std.mem.asBytes(&color));
            }
        }
    }
}

const Context = struct {
    compositor: ?*wl.Compositor,
    output: ?*wl.Output,
    shm: ?*wl.Shm,
    wm_base: ?*xdg.WmBase,

    layer_shell: ?*zwlr.LayerShellV1,
};

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.getInterface().name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.getInterface().name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Output.getInterface().name) == .eq) {
                context.output = registry.bind(global.name, wl.Output, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.getInterface().name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, zwlr.LayerShellV1.getInterface().name) == .eq) {
                context.layer_shell = registry.bind(global.name, zwlr.LayerShellV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, running: *bool) void {
    switch (event) {
        .configure => layer_surface.ackConfigure(event.configure.serial),
        .closed => running.* = false,
    }
}

const assets = @import("assets");

const colors = @import("colors.zig");
const Config = @import("config.zig").Config;
const config_parse_argv = @import("config.zig").parse_argv;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const freetype = @import("freetype");

const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const assert = std.debug.assert;
const log = std.log.scoped(.@"zig-prompt");
