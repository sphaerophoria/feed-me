const std = @import("std");

const Builder = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sphtud: *std.Build.Module,
    test_step: *std.Build.Step,

    fn init(b: *std.Build) Builder {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        return .{
            .b = b,
            .test_step = b.step("test", ""),
            .sphtud = b.dependency("sphtud", .{}).module("sphtud"),
            .target = target,
            .optimize = optimize,
        };
    }

    fn addDependencies(self: Builder, module: *std.Build.Module) void {
        module.addImport("sphtud", self.sphtud);
        module.addCSourceFile(.{
            .file = self.b.path("sqlite/sqlite3.c"),
        });
        module.addIncludePath(self.b.path("sqlite"));
        module.link_libc = true;
    }
};

pub fn build(b: *std.Build) void {
    const builder = Builder.init(b);

    const exe = b.addExecutable(.{
        .name = "feed_me",
        .root_source_file = b.path("src/main.zig"),
        .target = builder.target,
        .optimize = builder.optimize,
    });
    builder.addDependencies(exe.root_module);
    b.installArtifact(exe);

    const test_exe = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = builder.target,
        .optimize = builder.optimize,
    });

    builder.addDependencies(test_exe.root_module);
    const run_test = b.addRunArtifact(test_exe);
    builder.test_step.dependOn(&run_test.step);
}
