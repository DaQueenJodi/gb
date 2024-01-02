const std = @import("std");
const Module = std.build.Module;

pub fn gameboy(b: *std.build, hardware: *Module, instructions: *Module) *std.build.Module {
    return b.createModule(.{
        .source_file = .{ .path = "gameboy.zig" },
        .dependencies = &.{
            .{ .name = "hardware", .module = hardware },
            .{ .name = "instructions", .module = instructions },
        },
    });
}

pub fn build(b: *std.Build) void {
    // on by default becasue it's very slow without it rn
    const llvm = b.option(bool, "llvm", "") orelse true;
    const log_instrs = b.option(bool, "log_instrs", "") orelse false;

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
    exe.linkSystemLibrary("raylib");

    const generater = b.addExecutable(.{
        .name = "generate_instruction_logs",
        .root_source_file = .{ .path = "generate_instruction_logs.zig" },
    });


    const generater_step = b.addRunArtifact(generater);
    const generated_instructions_file = generater_step.addOutputFileArg("generated_instructions");

    const hardware = b.createModule(.{
        .source_file = .{ .path = "hardware/hardware.zig" },
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
