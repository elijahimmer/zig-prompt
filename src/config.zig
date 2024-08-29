pub const Config = struct {
    // general things
    arena: ArenaAllocator,
    program_name: [:0]const u8 = "zig-prompt",

    // params
    width: ?u31 = null,
    height: ?u31 = null,

    title: [:0]const u8 = "zig-prompt",

    background_color: Color = colors.main,
    text_color: Color = colors.text,

    border_width: u8 = 3,
    border_color: Color = colors.iris,

    font_size: u16 = 12,

    text: [][]u8 = undefined,

    pub fn deinit(self: *const @This()) void {
        self.arena.deinit();
    }

    pub fn parse_argv(allocator: std.mem.Allocator) !Config {
        var config = Config{ .arena = ArenaAllocator{ .child_allocator = allocator, .state = .{} } };
        const alloc = config.arena.allocator();

        var iter = try std.process.ArgIterator.initWithAllocator(alloc);
        defer iter.deinit();

        config.program_name = iter.next().?;

        var diag = clap.Diagnostic{};
        var res = clap.parse(clap.Help, &params, parsers, .{
            .diagnostic = &diag,
            .allocator = alloc,
        }) catch |err| {
            diag.report(std.io.getStdErr().writer(), err) catch {};
            exit(0);
        };
        defer res.deinit();

        if (res.args.help != 0) {
            clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{}) catch unreachable;
            exit(0);
        }

        if (res.args.width) |w| {
            config.width = w;
        }
        if (res.args.height) |h| {
            config.height = h;
        }
        if (res.args.title) |t| {
            const title = try alloc.allocSentinel(u8, t.len, 0);
            @memcpy(title, t);
            config.title = title;
        }
        if (res.args.background) |b| {
            config.background_color = b;
        }
        if (res.args.@"text-color") |T| {
            config.text_color = T;
        }
        if (res.args.@"font-size") |f| {
            config.font_size = f;
        }
        var seperator: []const u8 = " -> ";
        if (res.args.seperator) |s| {
            seperator = s;
        }

        if (res.positionals.len == 0) {
            print("You must provide some options to display!", .{});
            exit(0);
        }

        const lines = res.positionals.len;
        var text_buffer = try alloc.alloc([]u8, lines);

        for (res.positionals, 0..) |option, idx| {
            const text_length = option.key.len + seperator.len + option.desc.len;
            const text = try alloc.alloc(u8, text_length);

            @memcpy(text[0..option.key.len], option.key);
            @memcpy(text[option.key.len..][0..seperator.len], seperator);
            @memcpy(text[option.key.len..][seperator.len..][0..option.desc.len], option.desc);

            text_buffer[idx] = text;
        }

        config.text = text_buffer;

        return config;
    }
};

pub const Option = struct {
    key: []const u8,
    desc: []const u8,
};

const help =
    \\-h, --help                    Display this help and exit.
    \\-w, --width <INT>             The window's width
    \\-l, --height <INT>            The window's height
    \\-t, --title <STR>             The window's title
    \\-b, --background <COLOR>      The background color in hex
    \\-T, --text-color <COLOR>      The text color in hex
    \\-B, --border-color <COLOR>    The border color in hex
    \\    --border-size <INT>       The border size (default: 3)
    \\-s, --seperator <STR>         The seperator between each key and option
    \\    --font-size <INT>         The font size in points to use
    \\<OPTION> ...                  The options to enable {{KEY}}={{DESCRIPTION}}
    \\
;

const params = clap.parseParamsComptime(help);

fn color_parser(input: []const u8) std.fmt.ParseIntError!Color {
    return colors.int2Color(try clap.parsers.int(u32, 16)(input));
}

const OptionParserError = error{
    @"Option Syntax Error",
    @"Option Contains Illegal Null Character",
    @"Option Contains Invalid Unicode Character",
};

fn option_parser(input: []const u8) OptionParserError!Option {
    const seperator_idx = std.mem.indexOfScalar(u8, input, '=') orelse return error.@"Option Syntax Error";
    if (!(input.len >= 3)) return error.@"Option Syntax Error";
    if (std.mem.indexOfScalar(u8, input, 0) != null) return error.@"Option Contains Illegal Null Character";
    if (!std.unicode.utf8ValidateSlice(input[2..])) return error.@"Option Contains Invalid Unicode Character";

    return Option{
        .key = input[0..seperator_idx],
        .desc = input[seperator_idx + 1 ..],
    };
}

const parsers = .{
    .STR = clap.parsers.string,
    .INT = clap.parsers.int(u16, 10),
    .COLOR = color_parser,
    .OPTION = option_parser,
};

const assets = @import("assets");

const colors = @import("colors.zig");
const Color = colors.Color;

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const exit = std.process.exit;

const ArenaAllocator = std.heap.ArenaAllocator;

const clap = @import("clap");
