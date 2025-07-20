const std = @import("std");
const builtin = @import("builtin");

var global_target: ?std.Build.ResolvedTarget = null;

pub fn build(b: *std.Build) !void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    global_target = target;

    const build_nvim = b.option(
        bool,
        "build_nvim",
        "Fetch the source code for the neovim editor and build it and include the executable in the output.",
    ) orelse false;

    var nvim: ?*std.Build.Dependency = null;

    if (build_nvim) {
        nvim = b.lazyDependency("nvim", .{
            .target = target,
            .optimize = optimize,
        });
    }

    const zls = b.dependency("zls", .{
        .target = target,
        .optimize = optimize,
        .@"single-threaded" = false,
        .pie = true,
        // .strip = true,
        .@"use-llvm" = true,
    });

    b.installArtifact(zls.artifact("zls"));

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
        .{ .name = "treesitter_go", .scanner = false },
        .{ .name = "treesitter_javascript" },
        .{ .name = "treesitter_c_sharp" },
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
        .{ .name = "treesitter_diff", .scanner = false },
        .{ .name = "treesitter_asm", .scanner = false },
        .{ .name = "treesitter_godot_resource" },
        .{ .name = "treesitter_gdscript" },
        .{ .name = "treesitter_disassembly" },
        .{ .name = "treesitter_slint", .scanner = false },
        .{ .name = "treesitter_qml" },
        .{ .name = "treesitter_nix" },
        .{ .name = "treesitter_nim" },
        .{ .name = "treesitter_nasm", .scanner = false },
        .{ .name = "treesitter_haskell"},
    };

    if (nvim) |n| {
        const nvim_tls = n.builder.top_level_steps.get("nvim") orelse @panic("expected a step called nvim inside the nvim dependency");

        // traverse through steps and their dependencies to find the neovim artifact and generated files
        for (nvim_tls.step.dependencies.items) |dep| {
            std.debug.print("found dep with id: {}\n", .{dep.id});

            if (dep.cast(std.Build.Step.InstallArtifact)) |install_artifact| {
                const compile_step = install_artifact.artifact;
                // statically link neovim with libc, musl recommended
                compile_step.rdynamic = false;
                b.installArtifact(compile_step);
            }
            if (dep.cast(std.Build.Step.InstallDir)) |install_dir| {
                for (install_dir.step.dependencies.items) |idep| {
                    std.debug.print("found inner dep with id: {}\n", .{idep.id});

                    if (idep.cast(std.Build.Step.WriteFile)) |wf| {
                        b.installDirectory(.{
                            .source_dir = wf.getDirectory(),
                            .install_dir = .prefix,
                            .install_subdir = "runtime/",
                        });
                    }
                }
            }
        }

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
            std.debug.print("installing grammar {s}\n", .{parsername});
            b.getInstallStep().dependOn(add_ts_parser(b, parsername, path, grammar.scanner, target, optimize));
        }

        const markdown = b.dependency("treesitter_markdown", .{ .target = target, .optimize = optimize });
        b.getInstallStep().dependOn(add_ts_parser(b, "markdown", markdown.path("tree-sitter-markdown/"), true, target, optimize));
        b.getInstallStep().dependOn(add_ts_parser(b, "markdown_inline", markdown.path("tree-sitter-markdown-inline/"), true, target, optimize));
    }

    const fzf_step = buildFzfNative(b, target, optimize);
    b.getInstallStep().dependOn(fzf_step);

    const install_fzf_lib = b.step("install_fzf", "Install libfzf.dll into the plugin directory");
    install_fzf_lib.dependOn(installFzfNative(b));
    // full build must be completed before installation can happen
    install_fzf_lib.dependOn(b.getInstallStep());
}

fn dynlibExtensionForTarget(target: std.Build.ResolvedTarget) []const u8 {
    if (target.result.os.tag.isDarwin()) {
        return "dylib";
    } else if (target.result.os.tag == .windows) {
        return "dll";
    } else {
        return "so";
    }
}

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

    const install_path = b.fmt("parser/{s}.{s}", .{ name, dynlibExtensionForTarget(target) });
    const parser_install = b.addInstallArtifact(parser, .{ .dest_sub_path = install_path });
    return &parser_install.step;
}

fn buildFzfNative(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step {
    const fzf_lib = b.addLibrary(.{
        .name = "fzf",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });
    fzf_lib.addCSourceFile(.{ .file = b.path("pack/plugins/start/telescope-fzf-native.nvim/src/fzf.c") });
    fzf_lib.addIncludePath(b.path("pack/plugins/start/telescope-fzf-native.nvim/src"));
    fzf_lib.linkLibC();
    
    const install_path = b.fmt("fzf.{s}", .{ dynlibExtensionForTarget(target) });
    const install = b.addInstallArtifact(fzf_lib, .{ .dest_sub_path = install_path });
    return &install.step;
}

pub fn installFzfNative(b: *std.Build) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step) catch @panic("OOM");

    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "install_fzf",
        .makeFn = installFzfNativeMakeFn,
        .owner = b,
    });

    return step;
}

fn installFzfNativeMakeFn(step: *std.Build.Step, make_options: std.Build.Step.MakeOptions) anyerror!void {
    _ = make_options;
    const b = step.owner;
    const libname = b.fmt("fzf.{s}", .{ dynlibExtensionForTarget(global_target.?) });
    const relative_src = b.fmt("zig-out/lib/{s}", .{ libname });
    const relative_dest = "pack/plugins/start/telescope-fzf-native.nvim/build";
    const cwd = std.fs.cwd();
    // using ascii path should be fine, all ascii characters so on windows it is wtf8 compatible, in theory
    const dest_dir = try cwd.makeOpenPath(relative_dest, .{});
    try cwd.copyFile(relative_src, dest_dir, libname, .{});
}
