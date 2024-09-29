pub const Vector = struct {
    x: u31,
    y: u31,
};

pub const Quadrant = enum {
    top_right,
    top_left,
    bottom_left,
    bottom_right,
};

pub const DrawQuarterCircleArgs = struct {
    screen_buffer: *const ScreenBuffer,
    origin: Vector,
    radius: u31,
    quadrant: Quadrant,
    border_size: u16,

    inner_color: ?Color = null,
    border_color: Color,
    outer_color: ?Color = null,
};
pub fn draw_quarter_circle(args: DrawQuarterCircleArgs) void {
    const origin, const radius = .{ args.origin, args.radius };

    const height = args.screen_buffer.height;
    const width = args.screen_buffer.width;

    assert(origin.y < height);
    assert(origin.x < width);

    switch (args.quadrant) {
        .top_right => { // x far, y close
            assert(width > origin.x + radius);
            assert(origin.y >= radius);
        },
        .top_left => { // x close, y close
            assert(origin.x >= radius);
            assert(origin.y >= radius);
        },
        .bottom_left => { // x close, y far
            assert(origin.x >= radius);
            assert(height > origin.y + radius);
        },
        .bottom_right => { // x far, y far
            assert(width > origin.x + radius);
            assert(height > origin.y + radius);
        },
    }

    const x_start: i32 = switch (args.quadrant) {
        .top_left, .bottom_left => -@as(i32, @intCast(radius)),
        .top_right, .bottom_right => 0,
    };
    const y_start: i32 = switch (args.quadrant) {
        .top_left, .top_right => -@as(i32, @intCast(radius)),
        .bottom_left, .bottom_right => 0,
    };

    {
        var x = x_start;
        var y = y_start;

        log.debug("\t\tFilling circle", .{});
        while (x <= x_start + radius) {
            while (y <= y_start + radius) {
                const x_shifted: u31 = @intCast(x + origin.x);
                const y_shifted: u31 = @intCast(y + origin.y);

                const x_y = (x * x) + (y * y);
                const rad_sqr = (radius * radius);

                if (args.inner_color != null and x_y < rad_sqr) {
                    put_pixel(args.screen_buffer, .{ .x = x_shifted, .y = y_shifted }, args.inner_color.?);
                } else if (args.outer_color) |color| {
                    put_pixel(args.screen_buffer, .{ .x = x_shifted, .y = y_shifted }, color);
                }
                y += 1;
            }
            y = y_start;

            x += 1;
        }
    }

    log.debug("\t\tDrawing Circle Border", .{});
    for (0..args.border_size) |shift| {
        var x: i32 = radius;
        var y: i32 = 0;
        var t1: i32 = radius / 16;

        while (x >= y) {
            const vec = Vector{
                .x = @as(u31, @intCast(switch (args.quadrant) {
                    .top_left, .bottom_left => -x,
                    .top_right, .bottom_right => x,
                } + origin.x)),

                .y = @as(u31, @intCast(switch (args.quadrant) {
                    .top_left, .top_right => -y + @as(u31, @intCast(shift)),
                    .bottom_left, .bottom_right => y - @as(u31, @intCast(shift)),
                } + origin.y)),
            };
            put_pixel(args.screen_buffer, vec, args.border_color);
            const vec2 = Vector{
                .x = @as(u31, @intCast(switch (args.quadrant) {
                    .top_left, .bottom_left => -x + @as(u31, @intCast(shift)),
                    .top_right, .bottom_right => x - @as(u31, @intCast(shift)),
                } + origin.x)),

                .y = @as(u31, @intCast(switch (args.quadrant) {
                    .top_left, .top_right => -y,
                    .bottom_left, .bottom_right => y,
                } + origin.y)),
            };
            put_pixel(args.screen_buffer, vec2, args.border_color);
            const vec_mirrored = Vector{
                .x = @as(u31, @intCast(switch (args.quadrant) {
                    .bottom_right, .top_right => y - @as(u31, @intCast(shift)),
                    .bottom_left, .top_left => -y + @as(u31, @intCast(shift)),
                } + origin.x)),

                .y = @as(u31, @intCast(switch (args.quadrant) {
                    .bottom_right, .bottom_left => x,
                    .top_right, .top_left => -x,
                } + origin.y)),
            };
            put_pixel(args.screen_buffer, vec_mirrored, args.border_color);
            const vec2_mirrored = Vector{
                .x = @as(u31, @intCast(switch (args.quadrant) {
                    .bottom_right, .top_right => y,
                    .bottom_left, .top_left => -y,
                } + origin.x)),

                .y = @as(u31, @intCast(switch (args.quadrant) {
                    .bottom_right, .bottom_left => x - @as(u31, @intCast(shift)),
                    .top_right, .top_left => -x + @as(u31, @intCast(shift)),
                } + origin.y)),
            };
            put_pixel(args.screen_buffer, vec2_mirrored, args.border_color);

            y += 1;
            t1 += y;
            if (t1 > x) {
                t1 -= x;
                x -= 1;
            }
        }
    }
}

pub fn put_pixel(screen_buffer: *const ScreenBuffer, vec: Vector, color: Color) void {
    assert(vec.x < screen_buffer.width);
    assert(vec.y < screen_buffer.height);

    screen_buffer.screen[vec.y * screen_buffer.width + vec.x] = @bitCast(color);
}

//pub fn draw_quarter_circle(quadrant: Quadrant) void {}

const colors = @import("colors.zig");
const Color = colors.Color;

const DrawContext = @import("DrawContext.zig");
const ScreenBuffer = DrawContext.ScreenBuffer;

const std = @import("std");
const log = std.log.scoped(.drawing);
const assert = std.debug.assert;
