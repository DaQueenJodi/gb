const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const Instruction = @import("Instruction.zig");
const Memory = @import("Memory.zig");

const Cpu = @This();


mem: *Memory,
regs: Registers,

pub fn create(allocator: Allocator) !Cpu {
    return Cpu{
        .mem = try Memory.create(allocator),
        .regs = Registers.init(),
    };
}

pub fn nextByte(cpu: *Cpu) u8 {
    const b = cpu.mem.readByte(cpu.regs.pc);
    std.log.debug("b: {X:0>2}", .{b});
    cpu.regs.pc += 1;
    return b;
}

pub fn nextSignedByte(cpu: *Cpu) i8 {
    const b: i8 = @bitCast(cpu.mem.readByte(cpu.regs.pc));
    std.log.debug("b: {X:0>2}", .{b});
    cpu.regs.pc += 1;
    return b;
}
pub fn nextBytes(cpu: *Cpu) u16 {
    const bs = cpu.mem.readBytes(cpu.regs.pc);
    std.log.debug("bs: {X:0>4}", .{bs});
    cpu.regs.pc += 2;
    return bs;
}

fn jp(cpu: *Cpu, addr: u16) void {
    std.log.debug("jumping to {X:0>4}", .{addr});
    cpu.regs.pc = addr;
}
fn xor(cpu: *Cpu, n: u8) void {
    std.log.debug("XOR", .{});
    cpu.regs.set("A", n ^ cpu.regs.get("A"));
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(false);
}

fn dec(cpu: *Cpu, comptime s: []const u8) void {
    std.log.debug("DEC {s}", .{s});

    const r = cpu.regs.get(s);
    cpu.regs.set(s, r -% 1);
    cpu.regs.set_z(cpu.regs.get(s) == 0);
    cpu.regs.set_n(true);
    // TODO: test if this works lol
    // 4th would need to be borrowed if the first three bits are 0s
    const borrowed_4th = @ctz(cpu.regs.get(s)) >= 3 and r > 0;
    cpu.regs.set_h(!borrowed_4th);
}

fn rra(cpu: *Cpu) void {
    const a = cpu.regs.get("A");

    const c: u8 = @intFromBool(cpu.regs.get_c());
    const lsb = a & 0x01;

    const shifted = a >> 1;
    cpu.regs.set("A", shifted | (c << 7));
    cpu.regs.set_c(lsb == 1);
}

test "rra" {
    const t = std.testing;
    var cpu = Cpu{ .regs = .{}, .mem = undefined };
    cpu.regs.set("A", 0b01001100);
    cpu.regs.set_c(true);

    cpu.rra();

    try t.expectEqual(@as(u8, 0b10100110), cpu.regs.get("A"));
    try t.expect(!cpu.regs.get_c());
}


// yes im using a global variable, don't kill me
var instructions_until_enable_interupts: ?usize = null;
var instructions_until_disable_interupts: ?usize = null;
/// returns the number of clock cycles it should take to execute
pub fn execNextInstruction(cpu: *Cpu) usize {
    if (instructions_until_enable_interupts) |n| {
        if (n == 0) {
            instructions_until_enable_interupts = null;
            cpu.regs.ime = true;
        }
    }
    if (instructions_until_disable_interupts) |n| {
        if (n == 0) {
            instructions_until_disable_interupts = null;
            cpu.regs.ime = false;
        }
    }
    std.log.debug("pc: {X:0>4}", .{cpu.regs.pc});
    const b = cpu.nextByte();
    switch (b) {
        0x00 => return 4,
        // JP a16
        0xC3 => {
            cpu.jp(cpu.nextBytes());
            return 16;
        },
        // XOR A
        0xAF => {
            cpu.xor(cpu.regs.get("A"));
            return 4;
        },
        // LD HL, d16
        0x21 => {
            cpu.regs.set("HL", cpu.nextBytes());
            return 12;
        },
        // LD C, d8
        0x0E => {
            cpu.regs.set("C", cpu.nextByte());
            return 8;
        },
        // LD B, d8
        0x06 => {
            cpu.regs.set("B", cpu.nextByte());
            return 8;
        },
        // LD (HL-), A
        0x32 => {
            const addr = cpu.regs.get("HL");
            cpu.mem.writeByte(addr, cpu.regs.get("A"));
            cpu.dec("HL");
            return 12;
        },
        // DEC B
        0x05 => {
            cpu.dec("B");
            return 4;
        },
        // JR NZ, r8
        0x20 => {
            const n: i8 = @intCast(cpu.nextSignedByte());
            const pc_i: i32 = @intCast(cpu.regs.pc);
            if (!cpu.regs.get_z()) {
                cpu.jp(@intCast(pc_i + n));
                return 12;
            } else return 8;
        },
        // RRA
        0x1F => {
            cpu.rra();
            return 4;
        },
        // DEC H
        0x25 => {
            cpu.dec("H");
            return 4;
        },
        // DEC C
        0x0D => {
            cpu.dec("C");
            return 4;
        },
        // LD A, d8
        0x3E => {
            cpu.regs.set("A", cpu.nextByte());
            return 8;
        },
        // DI
        0xF3 => {
            instructions_until_disable_interupts = 2;
            return 4;
        },
        // LDH (a8), A
        0xE0 => {
            const off: u16 = @intCast(cpu.nextByte());
            const addr: u16 = off + 0xFF00;
            cpu.mem.writeByte(addr, cpu.regs.get("A"));
            return 12;
        },
        // LDH A, (a8)
        0xF0 => {
            const off: u16 = @intCast(cpu.nextByte());
            const addr: u16 = off + 0xFF00;
            const val = cpu.mem.readByte(addr);
            cpu.regs.set("A", val);
            return 12;
        },
        // CP d8
        0xFE => {
            // TODO: find a good (correct?) way to do the bit 4 borrow check
            const n = cpu.nextByte();
            const a = cpu.regs.get("A");

            const orig_bit_4 = (a & 0b00001000) >> 3 == 1;
            const new_bit_4 = ((a -% n) & 0b00001000) >> 3 == 1;

            const borrowed_4 = orig_bit_4 and !new_bit_4;

            cpu.regs.set_z(a == n);
            cpu.regs.set_n(true);
            cpu.regs.set_c(a < n);
            cpu.regs.set_h(borrowed_4);
            return 8;
        },
        // LD (HL), d8
        0x36 => {
            const n = cpu.nextByte();
            const addr = cpu.regs.get("HL");
            cpu.mem.writeByte(addr, n);
            return 12;
        },
        0xEA => {
            const a = cpu.regs.get("A");
            const addr = cpu.nextBytes();
            cpu.mem.writeByte(addr, a);
            return 16;
        },
        0x31 => {
            cpu.regs.set("SP", cpu.nextBytes());
            return 12;
        },
        else => std.debug.panic("invalid byte: 0x{X:0>2}", .{b}),
    }

    if (instructions_until_enable_interupts) |*n| n.* -= 1;
    if (instructions_until_disable_interupts) |*n| n.* -= 1;
}

test "combined registers" {
    const t = std.testing;
    var regs = Registers{};
    regs.set("B", 0b00100100);
    regs.set("C", 0b01110001);
    const combined: u16 = 0b00100100_01110001;
    try t.expectEqual(combined, regs.get("BC"));
}
