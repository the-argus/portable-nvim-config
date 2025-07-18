const std = @import("std");
const builtin = @import("builtin");

pub fn add_ts_parser(
    b: *std.Build,
    name: []const u8,
    parser_dir: std.Build.LazyPath,
    scanner: bool,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step {
    const parser = b.addLibrary(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });
    parser.addCSourceFile(.{ .file = parser_dir.path(b, "src/parser.c") });
    if (scanner) parser.addCSourceFile(.{ .file = parser_dir.path(b, "src/scanner.c") });
    parser.addIncludePath(parser_dir.path(b, "src"));
    parser.linkLibC();

    const lib_extension = block: {
        if (target.result.os.tag.isDarwin()) {
            break :block "dylib";
        } else if (target.result.os.tag == .windows) {
            break :block "lib";
        } else {
            break :block "so";
        }
    };

    const install_path = b.fmt("parser/{s}.{s}", .{ name, lib_extension });
    const parser_install = b.addInstallArtifact(parser, .{ .dest_sub_path = install_path });
    return &parser_install.step;
}

pub fn build(b: *std.Build) !void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_nvim = b.option(
        bool,
        "build_nvim",
        "Fetch the source code for the neovim editor and build it and include the executable in the output.",
    ) orelse false;

    // const download_fzf = b.option(
    //     bool,
    //     "download_fzf",
    //     "Download a binary of fzf for the target platform",
    // ) orelse true;

    var nvim: ?*std.Build.Dependency = null;
    // var fzf_bin: ?*std.Build.Dependency = null;

    if (build_nvim) {
        nvim = b.lazyDependency("nvim", .{ .target = target, .optimize = optimize });
    }

    // if (download_fzf) {
    //     const arch = target.result.cpu.arch;
    //     const os = target.result.os.tag;
    //     fzf_bin = switch (os) {
    //         .linux => switch (arch) {
    //             .x86_64 => b.lazyDependency("fzf_linux_amd64", .{}),
    //             .aarch64 => b.lazyDependency("fzf_linux_arm64", .{}),
    //             else => @panic("unsupported architecture for linux"),
    //         },
    //         .macos => switch (arch) {
    //             .x86_64 => b.lazyDependency("fzf_darwin_amd64", .{}),
    //             .aarch64 => b.lazyDependency("fzf_darwin_arm64", .{}),
    //             else => @panic("unsupported cpu architecture for macos"),
    //         },
    //         .windows => block: {
    //             if (arch != .x86_64) {
    //                 @panic("unsupported cpu architecture for windows");
    //             }
    //             break :block b.lazyDependency("fzf_windows_amd64", .{});
    //         },
    //         else => @panic("unsupported OS"),
    //     };
    // }
    //
    // if (fzf_bin) |fzf| {
    //     const install_step = b.addInstallBinFile(fzf.path("fzf"), "fzf");
    //     b.getInstallStep().dependOn(&install_step.step);
    // }

    const Grammar = struct {
        name: []const u8,
        subdir: ?[]const u8 = null,
        scanner: bool = true,
    };
    const grammars = &[_]Grammar{
        .{ .name = "treesitter_c", .scanner = false },
        .{ .name = "treesitter_cpp" },
        .{ .name = "treesitter_bash" },
        .{ .name = "treesitter_regex", .scanner = false },
        .{ .name = "treesitter_java", .scanner = false },
        .{ .name = "treesitter_css" },
        .{ .name = "treesitter_typescript", .subdir = "typescript" },
        .{ .name = "treesitter_html" },
        .{ .name = "treesitter_python" },
        .{ .name = "treesitter_json", .scanner = false },
        .{ .name = "treesitter_go",  .scanner = false },
        .{ .name = "treesitter_javascript" },
        .{ .name = "treesitter_c_sharp"  },
        .{ .name = "treesitter_rust" },
        .{ .name = "treesitter_printf", .scanner = false },
        .{ .name = "treesitter_toml" },
        .{ .name = "treesitter_yaml" },
        .{ .name = "treesitter_zig", .scanner = false },
        .{ .name = "treesitter_odin" },
        .{ .name = "treesitter_glsl", .scanner = false },
        .{ .name = "treesitter_hlsl" },
        .{ .name = "treesitter_make", .scanner = false },
        // markdown included manually
        .{ .name = "treesitter_lua" },
        .{ .name = "treesitter_vim" },
    };

    if (nvim) |_| {
        // const install_artifact = b.addInstallArtifact(n.artifact("nlua0"), .{});
        // b.getInstallStep().dependOn(&install_artifact.step);
        // b.getInstallStep().dependOn(n.builder.getInstallStep());

        for (grammars) |grammar| {
            const dep = b.dependency(grammar.name, .{ .target = target, .optimize = optimize });
            const offset = ("treesitter_").len;
            const path = block: {
                if (grammar.subdir) |subdir| {
                    break :block dep.path(subdir);
                }
                break :block dep.path(".");
            };
            const parsername = grammar.name[offset..];
            std.debug.print("installing grammar {s}\n", .{ parsername });
            b.getInstallStep().dependOn(add_ts_parser(b, parsername, path, grammar.scanner, target, optimize));
        }

        const markdown = b.dependency("treesitter_markdown", .{ .target = target, .optimize = optimize });
        b.getInstallStep().dependOn(add_ts_parser(b, "markdown", markdown.path("tree-sitter-markdown/"), true, target, optimize));
        b.getInstallStep().dependOn(add_ts_parser(b, "markdown_inline", markdown.path("tree-sitter-markdown-inline/"), true, target, optimize));
    }
}
