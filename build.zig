const std = @import("std");

const Scanner = @import("zig-wayland").Scanner;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addFmt(.{
        .check = true,
    });

    const exe = b.addExecutable(.{
        .name = "zig-prompt",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });

    const font_path = b.option([]const u8, "font-path", "Path to font to use") orelse "fonts/FiraCodeNerdFontMono-Regular.ttf";
    const font_file = std.fs.cwd().openFile(font_path, .{ .mode = .read_only }) catch @panic("Failed to open font file");
    const font_data = font_file.readToEndAlloc(b.allocator, 5_000_000) catch @panic("Failed to read font file");

    const options = b.addOptions();
    options.addOption([]const u8, "font_data", font_data);

    exe.step.dependOn(&options.step);
    exe.root_module.addOptions("assets", options);

    { // zig-clap
        const clap = b.dependency("clap", .{});
        exe.root_module.addImport("clap", clap.module("clap"));
    }

    { // mach-freetype
        const freetype = b.dependency("mach_freetype", .{});
        exe.root_module.addImport("freetype", freetype.module("mach-freetype"));
    }

    { // Wayland-zig
        const scanner = Scanner.create(b, .{
            .wayland_xml_path = "protocols/wayland.xml",
            .wayland_protocols_path = "protocols",
        });

        const wayland = b.createModule(.{ .root_source_file = scanner.result });

        scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
        scanner.addSystemProtocol("wlr/unstable/wlr-layer-shell-unstable-v1.xml");

        scanner.generate("wl_compositor", 2);
        scanner.generate("wl_shm", 2);
        scanner.generate("wl_output", 4);
        scanner.generate("xdg_wm_base", 2);
        scanner.generate("zwlr_layer_shell_v1", 4);

        exe.root_module.addImport("wayland", wayland);

        exe.linkSystemLibrary("wayland-client");

        // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented
        scanner.addCSource(exe);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
