pub fn main() anyerror!void {
    var config = try Config.parse_argv(std.heap.c_allocator);
    // no deinit- lives as long as program.

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();
    defer registry.destroy();

    var wayland_context = WaylandContext{
        .shm = null,
        .compositor = null,
        .output = null,
        .output_context = .{},
        .wm_base = null,
        .layer_shell = null,
    };

    registry.setListener(*WaylandContext, registryListener, &wayland_context);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const shm = wayland_context.shm orelse return error.@"No Wayland Shared Memory";
    defer shm.release();

    const compositor = wayland_context.compositor orelse return error.@"No Wayland Compositor";

    const output = wayland_context.output orelse return error.@"No Wayland Output";
    defer output.release();
    output.setListener(*OutputContext, outputListener, &wayland_context.output_context);

    //const wm_base = wayland_context.wm_base orelse return error.@"No Xdg Window Manager Base";
    const layer_shell = wayland_context.layer_shell orelse return error.@"No WlRoots Layer Shell";

    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    //if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    //assert(wayland_context.output_context.is_done);

    const buffer = buffer: {
        var draw_ctx = try DrawContext.init(std.heap.c_allocator, &wayland_context.output_context, &config);
        defer draw_ctx.deinit();

        // TODO: Make this a separate variable we keep so that if we need to resize or redraw, we can
        const screen_buffer = try draw_ctx.createScreenBuffer();
        defer screen_buffer.deinit();

        log.debug("height: {}, width: {}", .{ screen_buffer.height, screen_buffer.width });

        try draw_ctx.draw_window(&screen_buffer);

        config.height = @intCast(screen_buffer.height);
        config.width = @intCast(screen_buffer.width);

        const pool = try shm.createPool(screen_buffer.fd, screen_buffer.width * screen_buffer.height * 4);
        //// should I destroy the pool here?
        //defer pool.destroy();

        break :buffer try pool.createBuffer(0, @intCast(screen_buffer.width), @intCast(screen_buffer.height), @intCast(screen_buffer.width * 4), wl.Shm.Format.argb8888);
    };
    defer buffer.destroy();

    const surface = try compositor.createSurface();
    defer surface.destroy();

    const layer_surface = try layer_shell.getLayerSurface(surface, null, zwlr.LayerShellV1.Layer.top, "elijah-immer/zig-prompt");
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

const WaylandContext = struct {
    compositor: ?*wl.Compositor,
    output: ?*wl.Output,
    output_context: OutputContext,
    shm: ?*wl.Shm,
    wm_base: ?*xdg.WmBase,

    layer_shell: ?*zwlr.LayerShellV1,
};

pub const OutputContext = struct {
    width: ?u16 = null,
    height: ?u16 = null,
    physical_width: ?u16 = null,
    physical_height: ?u16 = null,
    is_done: bool = false,
};

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *WaylandContext) void {
    const listen_to = .{
        .{ wl.Compositor, "compositor" },
        .{ wl.Shm, "shm" },
        .{ wl.Output, "output" },
        .{ xdg.WmBase, "wm_base" },
        .{ zwlr.LayerShellV1, "layer_shell" },
    };

    switch (event) {
        .global => |global| {
            inline for (listen_to) |variable| {
                const resource, const field = variable;

                if (mem.orderZ(u8, global.interface, resource.getInterface().name) == .eq)
                    @field(context, field) = registry.bind(global.name, resource, 1) catch return;
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
    const logl = std.log.scoped(.@"zig-prompt.Output");
    _ = output;
    switch (event) {
        .geometry => |geometry| {
            ctx.physical_width = @intCast(geometry.physical_width);
            ctx.physical_height = @intCast(geometry.physical_height);
            logl.debug("geometry x: {}, y: {}, physical_width: {}, physical_height: {}", .{ geometry.x, geometry.y, geometry.physical_width, geometry.physical_height });
        },
        .mode => |mode| {
            ctx.width = @intCast(mode.width);
            ctx.height = @intCast(mode.height);
            logl.debug("mode flags: {}, width: {}, height: {}, refresh: {}", mode);
        },
        .done => {
            logl.debug("output is done", .{});
            ctx.is_done = true;
        },
        .scale, .name, .description => {},
    }
}

test {
    std.testing.refAllDecls(DrawContext);
    std.testing.refAllDecls(colors);
    std.testing.refAllDecls(@import("config.zig"));
    std.testing.refAllDecls(@import("wayland")); // make sure the wayland binds work
}

const DrawContext = @import("DrawContext.zig");
const colors = @import("colors.zig");
const Config = @import("config.zig").Config;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const freetype = @import("freetype");

const builtins = @import("builtins");
const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const assert = std.debug.assert;
const log = std.log.scoped(.@"zig-prompt");
