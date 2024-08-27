const Config = struct {
    width: u16 = 450, // way more than large enough.
    height: u16 = 450,

    window_title: *const [10:0]u8 = "zig-prompt",

    background_color: rl.Color = colors.main,
    text_color: rl.Color = colors.text,
};

pub fn main() anyerror!void {
    const config = Config{};

    rl.initWindow(config.width, config.height, config.window_title);
    defer rl.closeWindow();

    const monitor = rl.getCurrentMonitor();
    const refresh_rate = rl.getMonitorRefreshRate(monitor);
    log.info("monitor: {}, rr: {}", .{ monitor, refresh_rate });

    rl.setTargetFPS(refresh_rate);

    const window_config = .{
        .fullscreen_mode = false,
        .window_resizable = true,
        .window_undecorated = true,
        .borderless_windowed_mode = true,
    };

    rl.setWindowState(window_config);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(config.background_color);

        rl.drawFPS(0, 0);

        rl.drawText("Congrats! You created your first window!", 20, 100, 20, config.text_color);
    }
}

const colors = @import("colors.zig");

const std = @import("std");
const rl = @import("raylib");

const assert = std.debug.assert;
const log = std.log.scoped(.@"zig-prompt");
