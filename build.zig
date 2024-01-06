const std = @import("std");
const Module = std.build.Module;

fn gameboy(b: *std.build, hardware: *Module, instructions: *Module) *std.build.Module {
    return b.createModule(.{
        .source_file = .{ .path = "gameboy.zig" },
        .dependencies = &.{
            .{ .name = "hardware", .module = hardware },
            .{ .name = "instructions", .module = instructions },
        },
    });
}

fn tracy(b: *std.build, exe: *std.Build.Step.Compile) void {
    const tracy_dep = b.dependency("tracy_src", .{});
    const tracy_client = tracy_dep.path("public/TracyClient.cpp");
    const tracy_include = tracy_dep.path("public/tracy");
    exe.addIncludePath(tracy_include);

    exe.linkLibCpp();
    exe.linkSystemLibrary("dl");
    exe.linkSystemLibrary("pthread");
    exe.addCSourceFile(.{
        .file = tracy_client,
        .flags = &.{},
    });
    exe.defineCMacro("TRACY_ENABLE", "");
}

pub fn build(b: *std.Build) void {
    // on by default becasue it's very slow without it rn
    const llvm = b.option(bool, "llvm", "") orelse true;
    const log_instrs = b.option(bool, "log_instrs", "") orelse false;
    const enable_tracy = b.option(bool, "tracy", "") orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "tracy", enable_tracy);
    const build_options_module = build_options.createModule();

    const c = b.createModule(.{
        .source_file = .{.path = "c.zig"},
        .dependencies = &.{
            .{.name = "build_options", .module = build_options_module},
        },
    });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "gb",
        .root_source_file = .{ .path = "main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.use_llvm = llvm;
    exe.use_lld = llvm;

    exe.linkLibC();
    exe.linkSystemLibraryPkgConfigOnly("SDL2");

    exe.addModule("c", c);

    if (enable_tracy) {
        tracy(b, exe);
    }

    const generater = b.addExecutable(.{
        .name = "generate_instruction_logs",
        .root_source_file = .{ .path = "generate_instruction_logs.zig" },
    });

    const generater_step = b.addRunArtifact(generater);
    const generated_instructions_file = generater_step.addOutputFileArg("generated_instructions");

    const hardware = b.createModule(.{
        .source_file = .{ .path = "hardware/hardware.zig" },
        .dependencies = &.{
            .{ .name = "c", .module = c },
        },
    });
    const instructions_deps = &.{
        std.build.ModuleDependency{ .name = "hardware", .module = hardware },
    };
    const original_instructions = b.createModule(.{
        .source_file = .{ .path = "instructions.zig" },
        .dependencies = instructions_deps,
    });
    const generated_instructions = b.createModule(.{
        .source_file = generated_instructions_file,
        .dependencies = instructions_deps,
    });

    const gameboy_with_logs = gameboy(b, hardware, generated_instructions); 
    const gameboy_without_logs = gameboy(b, hardware, original_instructions);

    exe.addModule("gameboy", if (log_instrs) gameboy_with_logs else gameboy_without_logs);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "tests/jsmoo_tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    // never use logs for unit tests
    exe_unit_tests.addModule("gameboy", gameboy_without_logs);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
