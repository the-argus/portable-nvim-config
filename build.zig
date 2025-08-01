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
    ) orelse true;

    var nvim: ?*std.Build.Dependency = null;

    if (build_nvim) {
        nvim = b.lazyDependency("neovim", .{
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

    if (nvim) |n| {
        const nvim_tls = n.builder.top_level_steps.get("nvim") orelse @panic("expected a step called nvim inside the nvim dependency");

        // traverse through steps and their dependencies to find the neovim artifact and generated files
        for (nvim_tls.step.dependencies.items) |dep| {
            // the only top level artifact is nvim
            if (dep.cast(std.Build.Step.InstallArtifact)) |install_artifact| {
                const compile_step = install_artifact.artifact;
                // statically link neovim with libc, musl recommended
                compile_step.rdynamic = false;
                b.installArtifact(compile_step);
            }

            // recurse to find runtime/ file installs etc
            stealInstalls(b, dep);
        }

        // manually install runtime elements of neovim, all the .vim .lua .spl
        // etc files
        const src = try n.builder.build_root.handle.openDir("runtime", .{ .iterate = true });
        var walker = try src.walk(b.allocator);

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            const ext = std.fs.path.extension(entry.basename);
            const basename = std.fs.path.basename(entry.basename);
            var bad = false;
            const bad_extensions = [_][]const u8{ ".zig", "" };
            const bad_filenames = [_][]const u8{"CMakeLists.txt"};
            for (bad_extensions) |bad_ext| {
                if (std.mem.eql(u8, ext, bad_ext)) {
                    bad = true;
                    break;
                }
            }
            for (bad_filenames) |bad_name| {
                if (std.mem.eql(u8, basename, bad_name)) {
                    bad = true;
                    break;
                }
            }
            if (bad) {
                // std.debug.print("deleted {s}\n", .{entry.path});
                continue;
            }

            const sub_path = b.pathJoin(&.{ "runtime", entry.path });
            const install_step = b.addInstallFile(
                std.Build.LazyPath{ .src_path = .{
                    .owner = n.builder,
                    .sub_path = sub_path,
                } },
                sub_path,
            );

            b.getInstallStep().dependOn(&install_step.step);
        }
    }

    const fzf_step = buildFzfNative(b, target, optimize);
    b.getInstallStep().dependOn(fzf_step);

    const install_fzf_lib = b.step("install_fzf", "Install libfzf.dll into the plugin directory");
    install_fzf_lib.dependOn(installFzfNative(b));
    // full build must be completed before installation can happen
    install_fzf_lib.dependOn(b.getInstallStep());
}

/// function meant specifically for the build graph of neovim
fn stealInstalls(b: *std.Build, victim: *std.Build.Step) void {

    // steal the nvim runstep which depends on stuff already being installed in
    // runtime/ dir. this generates docs and things
    if (victim.cast(std.Build.Step.Run)) |runstep| {
        for (runstep.step.dependencies.items) |idep| {
            if (idep.cast(std.Build.Step.InstallDir)) |id| {
                const install_path: std.Build.LazyPath = .{ .cwd_relative = b.install_path };
                runstep.setCwd(install_path.path(b, "runtime/"));
                // actually make the install directory go to our output
                id.step.owner = b;
            }
        }
    }

    // find WriteFile under InstallDir which is the syntax/generated.vim file
    if (victim.cast(std.Build.Step.InstallDir)) |id| {
        for (id.step.dependencies.items) |idep| {
            if (idep.cast(std.Build.Step.WriteFile)) |wf| {
                b.installDirectory(.{
                    .source_dir = wf.getDirectory(),
                    .install_dir = .prefix,
                    .install_subdir = "runtime/",
                });
            }
        }
    }

    for (victim.dependencies.items) |dep| {
        stealInstalls(b, dep);
    }
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

    const install_path = b.fmt("fzf.{s}", .{dynlibExtensionForTarget(target)});
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
    const libname = b.fmt("fzf.{s}", .{dynlibExtensionForTarget(global_target.?)});
    const relative_src = b.fmt("zig-out/lib/{s}", .{libname});
    const relative_dest = "pack/plugins/start/telescope-fzf-native.nvim/build";
    const cwd = std.fs.cwd();
    // using ascii path should be fine, all ascii characters so on windows it is wtf8 compatible, in theory
    const dest_dir = try cwd.makeOpenPath(relative_dest, .{});
    try cwd.copyFile(relative_src, dest_dir, libname, .{});
}
