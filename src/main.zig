const ConfigFlags = packed struct(c_int) {
    _reserved1: u1 = 0,
    fullscreen_mode: bool = false,
    window_resizable: bool = false,
    window_undecorated: bool = false,
    window_transparent: bool = false,
    _reserved2: u10 = 0,
    borderless_windowed_mode: bool = false,
    _reserved3: u16 = 0,
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = try config_parse_argv(gpa.allocator());
    defer config.deinit();

    const text_width = @as(u31, @intCast(rl.MeasureText(config.text, config.font_size)));
    const text_height = config.lines * config.font_size;
    const window_width = config.width orelse (text_width * 11) / 10; // add 10% margin
    const window_height = config.height orelse (text_height * 11) / 10;

    assert(window_width >= text_width);
    assert(window_height >= text_height);

    rl.InitWindow(window_width, window_height, config.title);
    defer rl.CloseWindow();

    const monitor = rl.GetCurrentMonitor();
    const refresh_rate = rl.GetMonitorRefreshRate(monitor);
    log.info("monitor: {}, rr: {}", .{ monitor, refresh_rate });

    rl.SetTargetFPS(refresh_rate);

    //const window_config = ConfigFlags{
    //    .fullscreen_mode = false,
    //    .window_resizable = true,
    //    .window_undecorated = true,
    //    .borderless_windowed_mode = true, // makes the window not floating in hyprland
    //};

    //rl.SetWindowState(@bitCast(window_config));

    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(config.background);

        rl.DrawFPS(0, 0);

        const text_pos_x = (window_width -| text_width) / 2;
        const text_pos_y = (window_height -| text_height) / 2;

        rl.DrawText(config.text, text_pos_x, text_pos_y, config.font_size, config.foreground);
    }
}

const colors = @import("colors.zig");
const config_parse_argv = @import("config.zig").parse_argv;

const std = @import("std");
const rl = @cImport({
    @cInclude("raylib.h");
});

const assert = std.debug.assert;
const log = std.log.scoped(.@"zig-prompt");
