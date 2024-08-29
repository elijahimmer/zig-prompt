pub const Config = struct {
    // general things
    arena: ArenaAllocator,
    program_name: []const u8,

    // params
    width: ?u16,
    height: ?u16,

    title: []const u8,

    background_color: Color,
    text_color: Color,

    border_size: u8,
    border_color: Color,

    font_size: u16,

    options: []const Option,
    seperator: []const u8,

    pub fn deinit(self: *const @This()) void {
        self.arena.deinit();
    }

    pub fn parse_argv(allocator: std.mem.Allocator) !Config {
        var arena = ArenaAllocator.init(allocator);
        const alloc = arena.allocator();

        var iter = try std.process.ArgIterator.initWithAllocator(alloc);
        defer iter.deinit();

        const program_name = iter.next() orelse "zig-prompt";

        var diag = clap.Diagnostic{};
        var res = clap.parse(clap.Help, &params, parsers, .{
            .diagnostic = &diag,
            .allocator = alloc,
        }) catch |err| {
            diag.report(std.io.getStdErr().writer(), err) catch {};
            exit(0);
        };

        const args = &res.args;

        if (args.help != 0) {
            clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{}) catch unreachable;
            exit(0);
        }

        if (res.positionals.len == 0) {
            print("You must provide some options to display!", .{});
            exit(0);
        }

        return Config{
            .arena = arena,
            .program_name = program_name,

            .width = args.width,
            .height = args.height,

            .background_color = args.@"background-color" orelse colors.main,
            .text_color = args.@"text-color" orelse colors.text,

            .font_size = @intCast(args.@"font-size" orelse 20),

            .border_size = @intCast(args.@"border-size" orelse 3),
            .border_color = args.@"border-color" orelse colors.iris,

            .title = args.title orelse "zig-prompt",

            .options = res.positionals,
            .seperator = args.seperator orelse " -> ",
        };
    }
};

pub const Option = struct {
    key: []const u8,
    desc: []const u8,
};

const help =
    \\-h, --help                     Display this help and exit.
    \\-w, --width <INT>              The window's width
    \\-l, --height <INT>             The window's height
    \\-t, --title <STR>              The window's title
    \\-b, --background-color <COLOR> The background color in hex
    \\-T, --text-color <COLOR>       The text color in hex
    \\-B, --border-color <COLOR>     The border color in hex
    \\    --border-size <INT>        The border size (default: 3)
    \\-s, --seperator <STR>          The seperator between each key and option
    \\    --font-size <INT>          The font size in points to use
    \\<OPTION> ...                   The options to enable {{KEY}}={{DESCRIPTION}}
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

const option_seperators = "=";

fn option_parser(input: []const u8) OptionParserError!Option {
    const seperator_idx = std.mem.indexOf(u8, input, option_seperators) orelse return error.@"Option Syntax Error";
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
