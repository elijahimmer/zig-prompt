pub const Config = struct {
    // general things
    arena: ArenaAllocator,
    program_name: []const u8,

    // params
    width: ?u16,
    height: ?u16,

    title: []const u8,

    background_color: Color,
    key_color: Color,
    separator_color: Color,
    desc_color: Color,

    border_size: u16,
    border_color: Color,

    font_size: u16,

    padding_left: u16,
    padding_right: u16,
    padding_top: u16,
    padding_bottom: u16,

    options: []const Option,
    separator: []const u8,

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
            clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{}) catch {};
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

            .background_color = args.@"background-color" orelse all_colors.main,
            .key_color = args.@"key-color" orelse args.@"text-color" orelse all_colors.text,
            .separator_color = args.@"separator-color" orelse args.@"text-color" orelse all_colors.text,
            .desc_color = args.@"desc-color" orelse args.@"text-color" orelse all_colors.text,

            .font_size = args.@"font-size" orelse 20,

            .border_size = args.@"border-size" orelse 2,
            .border_color = args.@"border-color" orelse all_colors.iris,

            .padding_left = args.@"padding-left" orelse args.padding orelse 3,
            .padding_right = args.@"padding-right" orelse args.padding orelse 3,
            .padding_top = args.@"padding-top" orelse args.padding orelse 3,
            .padding_bottom = args.@"padding-bottom" orelse args.padding orelse 3,

            .title = args.title orelse std.mem.span(std.os.argv[0]),

            .options = res.positionals,
            .separator = args.separator orelse " ",
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
    \\    --key-color <COLOR>        The text color for the keys in hex (overrides -T for keys)
    \\    --separator-color <COLOR>  The text color for the separators in hex (overrides -T for separators)
    \\    --desc-color <COLOR>       The text color for the descriptions in hex (overrides -T for descriptions)
    \\    --border-color <COLOR>     The border color in hex
    \\    --border-size <INT>        The border size (default: 2)
    \\-s, --separator <STR>          The separator between each key and option
    \\    --font-size <INT>          The font size in points to use
    \\-p, --padding <INT>            The padding size in pixels between the text and the border (default: 3)
    \\    --padding-left <INT>       The padding on the left side (overrides -p for this side)
    \\    --padding-right <INT>      The padding on the right side (overrides -p for this side)
    \\    --padding-top <INT>        The padding on the top (overrides -p for this side)
    \\    --padding-bottom <INT>     The padding on the bottom (overrides -p for this side)
    \\<OPTION> ...                   The options to enable {{KEY}}={{DESCRIPTION}}
    \\
;

const params = clap.parseParamsComptime(help);

const OptionParserError = error{
    @"Option Syntax Error",
    @"Option Contains Illegal Null Character",
    @"Option Contains Invalid Unicode Character",
    @"Option must contain a key",
    @"Option must contain a description",
};

const option_separators = "=";

fn option_parser(input: []const u8) OptionParserError!Option {
    const separator_idx = std.mem.indexOf(u8, input, option_separators) orelse return error.@"Option Syntax Error";

    if (!(input.len >= 3)) return error.@"Option Syntax Error";
    if (std.mem.indexOfScalar(u8, input, 0) != null) return error.@"Option Contains Illegal Null Character";
    if (!std.unicode.utf8ValidateSlice(input)) return error.@"Option Contains Invalid Unicode Character";

    const key = input[0..separator_idx];
    const desc = input[separator_idx + 1 ..];

    if (key.len == 0) return error.@"Option must contain a key";
    if (desc.len == 0) return error.@"Option must contain a description";

    return Option{ .key = key, .desc = desc };
}

const parsers = .{
    .STR = clap.parsers.string,
    .INT = clap.parsers.int(u16, 10),
    .COLOR = colors.str2Color,
    .OPTION = option_parser,
};

const assets = @import("assets");

const colors = @import("colors.zig");
const Color = colors.Color;
const all_colors = colors.all_colors;

const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const exit = std.process.exit;

const ArenaAllocator = std.heap.ArenaAllocator;

const clap = @import("clap");
