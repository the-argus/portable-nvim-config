const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_nvim = b.option(
        bool,
        "build_nvim",
        "Fetch the source code for the neovim editor and build it and include the executable in the output.",
    ) orelse false;

    const nvim: ?*std.Build.Dependency = null;

    if (build_nvim) {
        nvim = b.lazyDependency("nvim", .{ .target = target, .optimize = optimize });
    }
}
