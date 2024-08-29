pub fn main() anyerror!void {
    var config = try Config.parse_argv(std.heap.page_allocator);

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var wayland_context = Context{
        .shm = null,
        .compositor = null,
        .output = null,
        .output_context = .{},
        .wm_base = null,
        .layer_shell = null,
    };

    registry.setListener(*Context, registryListener, &wayland_context);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const shm = wayland_context.shm orelse return error.@"No Wayland Shared Memory";
    defer shm.release();

    const compositor = wayland_context.compositor orelse return error.@"No Wayland Compositor";

    //const output = wayland_context.output orelse return error.@"No Wayland Output";
    //defer output.release();
    //output.setListener(*OutputContext, outputListener, &wayland_context.output_context);

    //const wm_base = wayland_context.wm_base orelse return error.@"No Xdg Window Manager Base";
    const layer_shell = wayland_context.layer_shell orelse return error.@"No WlRoots Layer Shell";

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const buffer = buffer: {
        const draw_ctx = try DrawContext.init(&config);
        const screen_buffer = try draw_ctx.createScreenBuffer();

        log.debug("height: {}, width: {}", .{ screen_buffer.height, screen_buffer.width });

        try draw_ctx.draw_window(&screen_buffer);

        const pool = try shm.createPool(screen_buffer.fd, screen_buffer.width * screen_buffer.height);
        defer pool.destroy();

        break :buffer try pool.createBuffer(0, @intCast(screen_buffer.width), @intCast(screen_buffer.height), @intCast(screen_buffer.width * 4), wl.Shm.Format.argb8888);
    };
    defer buffer.destroy();

    const surface = try compositor.createSurface();
    defer surface.destroy();

    const layer_surface = try layer_shell.getLayerSurface(surface, null, zwlr.LayerShellV1.Layer.top, "elijah-immer/wayprompt");
    defer layer_surface.destroy();

    layer_surface.setSize(config.width.?, config.height.?);
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

const Context = struct {
    compositor: ?*wl.Compositor,
    output: ?*wl.Output,
    output_context: OutputContext,
    shm: ?*wl.Shm,
    wm_base: ?*xdg.WmBase,

    layer_shell: ?*zwlr.LayerShellV1,
};

const OutputContext = struct {
    width: ?u16 = null,
    height: ?u16 = null,
    physical_width: ?u16 = null,
    physical_height: ?u16 = null,
    is_done: bool = false,
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
        .configure => |configure| layer_surface.ackConfigure(configure.serial),
        .closed => running.* = false,
    }
}

fn outputListener(output: *wl.Output, event: wl.Output.Event, ctx: *OutputContext) void {
    const logz = std.log.scoped(.@"zig-prompt.Output");
    _ = output;
    switch (event) {
        .geometry => |geometry| {
            ctx.physical_width = @intCast(geometry.physical_width);
            ctx.physical_height = @intCast(geometry.physical_height);
            logz.debug("geometry x: {}, y: {}, physical_width: {}, physical_height: {}", .{ geometry.x, geometry.y, geometry.physical_width, geometry.physical_height });
        },
        .mode => |mode| {
            ctx.width = @intCast(mode.width);
            ctx.height = @intCast(mode.height);
            logz.debug("mode flags: {}, width: {}, height: {}, refresh: {}", mode);
        },
        .done => {
            ctx.is_done = true;
        },
        .scale, .name, .description => {},
    }
}

const DrawContext = @import("DrawContext.zig");
const colors = @import("colors.zig");
const Config = @import("config.zig").Config;

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
