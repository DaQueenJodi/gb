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
    ime: u1,
    ram: [][2]u16,
};

const Test = struct {
    name: []const u8,
    initial: Config,
    final: Config,
    cycles: []std.json.Value,
};

// TOOD: ie
fn configToCpu(allocator: Allocator, config: Config) !Cpu {
    var mem = try allocator.create(Memory);
    mem.rom_mapped = false;

    // TODO: desmellify this
    for (config.ram) |r| {
        const addr = r[0];
        if (addr < 0x4000) {
            mem.bank0[addr] = @intCast(r[1]);
        } else {
            mem.bank1[addr - 0x4000] = @intCast(r[1]);
        }
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
    regs.ime = config.ime == 1;

    return Cpu{
        .ime_scheduled = false,
        .mem = mem,
        .regs = regs,
    };
}
const REG_TABLE = [_]struct { l: []const u8, u: []const u8 }{
    .{ .l = "a", .u = "A" },
    .{ .l = "b", .u = "B" },
    .{ .l = "c", .u = "C" },
    .{ .l = "d", .u = "D" },
    .{ .l = "e", .u = "E" },
    .{ .l = "f", .u = "F" },
    .{ .l = "h", .u = "H" },
    .{ .l = "l", .u = "L" },
    .{ .l = "sp", .u = "SP" },
    .{ .l = "pc", .u = "PC" },
};
fn cmpCpuConfig(cpu: Cpu, config: Config) !void {
    const t = std.testing;
    inline for (REG_TABLE) |r| {
        try t.expectEqual(cpu.regs.get(r.u), @field(config, r.l));
    }
    for (config.ram) |r| {
        const addr = r[0];
        try t.expectEqual(cpu.mem.readByte(addr), @intCast(r[1]));
    }
}

fn readFile(alloc: Allocator, path: []const u8) ![]const u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    const stat = try f.stat();
    const buf = try alloc.alloc(u8, stat.size);
    _ = try f.readAll(buf);
    return buf;
}

test  {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const json = try readFile(alloc, "tests/jsmoo/00.json");
    const tests = try std.json.parseFromSliceLeaky([]Test, alloc, json, .{ .ignore_unknown_fields = true });
    for (tests) |te| {
        var cpu = try configToCpu(alloc, te.initial);
        try t.expectEqual(execNextInstruction(&cpu), te.cycles.len * 4);
        try cmpCpuConfig(cpu, te.final);
    }
}
