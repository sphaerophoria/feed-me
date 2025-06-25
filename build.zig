const std = @import("std");

const Builder = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    wasm_target: std.Build.ResolvedTarget,
    wasm_optimize: std.builtin.OptimizeMode,
    optimize: std.builtin.OptimizeMode,
    sphtud: *std.Build.Module,
    test_step: *std.Build.Step,

    fn init(b: *std.Build) Builder {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});
        const wasm_optimize = b.option(std.builtin.OptimizeMode, "wasm-opt", "") orelse .Debug;

        const wasm_target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        });


        return .{
            .b = b,
            .test_step = b.step("test", ""),
            .sphtud = b.dependency("sphtud", .{}).module("sphtud"),
            .target = target,
            .optimize = optimize,
            .wasm_optimize = wasm_optimize,
            .wasm_target = wasm_target,
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

    fn makeRunTest(self: Builder, path: []const u8) void {
        const test_exe = self.b.addTest(.{
            .root_source_file = self.b.path(path),
            .target = self.target,
            .optimize = self.optimize,
        });

        self.addDependencies(test_exe.root_module);
        const run_test = self.b.addRunArtifact(test_exe);
        self.test_step.dependOn(&run_test.step);
    }

    fn makeWasmExe(self: Builder, name: []const u8, path: []const u8) void {
        const wasm_exe = self.b.addExecutable(.{
            .name = name,
            .root_source_file = self.b.path(path),
            .target = self.wasm_target,
            .optimize = self.wasm_optimize,
        });

        wasm_exe.entry = .disabled;
        wasm_exe.rdynamic = true;
        wasm_exe.want_lto = true;

        self.b.installArtifact(wasm_exe);
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

    //const json = b.addExecutable(.{
    //    .name = "json_test",
    //    .root_source_file = b.path("src/json_parser.zig"),
    //    .target = builder.target,
    //    .optimize = builder.optimize,
    //});
    //json.root_module.addImport("sphtud", builder.sphtud);
    //b.installArtifact(json);

    builder.makeRunTest("src/main.zig");
    builder.makeRunTest("src/wasm/htmlgen.zig");

    builder.makeWasmExe("ingredient", "src/wasm/ingredient.zig");
    builder.makeWasmExe("ingredients", "src/wasm/ingredients.zig");
    builder.makeWasmExe("json_parser_2", "src/json_parser_2.zig");
    builder.makeWasmExe("json_parser", "src/wasm/json_test.zig");
}
