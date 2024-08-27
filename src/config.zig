pub const Config = struct {
    // general things
    arena: ArenaAllocator,
    program_name: [:0]const u8 = "zig-prompt",

    // params
    width: ?u16 = null, // way more than large enough.
    height: ?u16 = null,

    title: [:0]const u8 = "zig-prompt",

    background: Color = colors.main,
    foreground: Color = colors.text,

    font_size: u16 = 12,

    text: [:0]const u8 = "placeholder",
    lines: u16 = 0,

    pub fn deinit(self: *const @This()) void {
        self.arena.deinit();
    }
};

pub const Option = struct {
    key: u8,
    desc: []const u8,
};

const help =
    \\-h, --help                Display this help and exit.
    \\-w, --width <INT>         The window's width
    \\-l, --height <INT>        The window's height
    \\-t, --title <STR>         The window's title
    \\-b, --background <COLOR>  The background color in base 16
    \\-f, --foreground <COLOR>  The foreground color in base 16
    \\-s, --seperator <STR>     The seperator between each key and option
    \\    --font-size <INT>     The font size to use
    \\<OPTION> ...              The options to enable {{KEY}}={{DESCRIPTION}}
    \\
;

const params = clap.parseParamsComptime(help);

fn color_parser(input: []const u8) std.fmt.ParseIntError!Color {
    return colors.int2Color(try clap.parsers.int(u32, 16)(input));
}

const OptionParserError = error{
    @"Option Syntax Error",
    @"Option Contains Illegal Null Character",
    @"Option Contains Invalid Unicode",
};

fn option_parser(input: []const u8) !Option {
    if (!(input.len >= 3) or input[1] != '=') return error.@"Option Syntax Error";
    if (std.mem.indexOfScalar(u8, input, 0) != null) return error.@"Option Contains Illegal Null Character";
    if (!std.unicode.utf8ValidateSlice(input[2..])) return error.@"Option Contains Invalid Unicode Character";

    return Option{
        .key = input[0],
        .desc = input[2..],
    };
}

const parsers = .{
    .STR = clap.parsers.string,
    .INT = clap.parsers.int(u16, 10),
    .COLOR = color_parser,
    .OPTION = option_parser,
};

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
        config.background = b;
    }
    if (res.args.foreground) |f| {
        config.foreground = f;
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

    var text_len = res.positionals.len * (2 + seperator.len); // 1 for character, 1 for newline at end

    for (res.positionals) |o| text_len += o.desc.len;

    var text_buffer = try alloc.allocSentinel(u8, text_len, 0);

    var cursor: usize = 0;

    for (res.positionals) |option| {
        text_buffer[cursor] = option.key;
        cursor += 1;
        @memcpy(text_buffer[cursor..][0..seperator.len], seperator);
        cursor += seperator.len;
        @memcpy(text_buffer[cursor..][0..option.desc.len], option.desc);
        cursor += option.desc.len;
        text_buffer[cursor] = '\n';
        cursor += 1;
        config.lines += 1;
    }

    config.text = text_buffer;

    return config;
}

const colors = @import("colors.zig");
const Color = colors.Color;

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const exit = std.process.exit;

const ArenaAllocator = std.heap.ArenaAllocator;

const clap = @import("clap");
