const std = @import("std");

pub fn build(b: *std.Build) void {
    const llvm = b.option(bool, "llvm", "") orelse false;
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
    const generated_instructions = generater_step.addOutputFileArg("generated_instructions");

    const log_instrs = b.option(bool, "log_instrs", "") orelse true;

    const original_instructions_src = std.build.LazyPath{ .path = "instructions.zig" };
    const instructions_src: std.build.LazyPath = if (log_instrs) generated_instructions else original_instructions_src;

    const hardware = b.createModule(.{
        .source_file = .{ .path = "hardware.zig" },
    });
    const instructions = b.addModule("instructions", .{
        .source_file = instructions_src,
        .dependencies = &.{.{ .name = "gameboy", .module = hardware }},
    });
    const gameboy = b.createModule(.{
        .source_file = .{ .path = "gameboy.zig" },
        .dependencies = &.{
            .{ .name = "hardware", .module = hardware },
            .{ .name = "instructions", .module = instructions },
        },
    });

    exe.addModule("gameboy", gameboy);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "jsmoo_tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.addModule("gameboy", gameboy);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
