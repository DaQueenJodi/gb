const std = @import("std");
const Allocator = std.mem.Allocator;
const GB = @import("gameboy");
const execNextInstruction = GB.execNextInstruction;
const Cpu = GB.Cpu;
const Registers = GB.Registers;
const Memory = GB.Memory;

const Config = struct {
    pc: u16,
    sp: u16,
    a: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    f: u8,
    h: u8,
    l: u8,
    ime: bool,
    ie: bool,
    ram: [][2]u16,
};

const Test = struct {
    name: []const u8,
    initial: Config,
    final: Config,
    cycles: [3][]const u8,
};

// TOOD: ie
fn configToCpu(allocator: Allocator, config: Config) !Cpu {
    var mem = try allocator.create(Memory);
    mem.rom_mapped = false;

    for (config.ram) |r| {
        mem.writeByte(r[0], @intCast(r[1]));
    }

    var regs: Registers = undefined;
    regs.set("PC", config.pc);
    regs.set("SP", config.sp);
    regs.set("A", config.a);
    regs.set("B", config.b);
    regs.set("C", config.c);
    regs.set("D", config.d);
    regs.set("E", config.e);
    regs.set("F", config.f);
    regs.set("L", config.l);
    regs.ime = true;

    return Cpu{
        .ime_scheduled = false,
        .mem = mem,
        .regs = regs,
    };
}

test "00" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const json = @embedFile("tests/jsmoo/00.json");

    const tests = try std.json.parseFromSliceLeaky([]Test, alloc, json, .{});
    const te = tests[0];
    var cpu = try configToCpu(alloc, te.initial);
    try t.expectEqual(execNextInstruction(&cpu), te.cycles.len * 4);
}
