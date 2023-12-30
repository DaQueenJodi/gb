const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;



const Registers = @import("Registers.zig");
const Memory = @import("Memory.zig");
const instructions = @import("instructions");

const Cpu = @This();


ime_scheduled: bool,
mem: *Memory,
regs: Registers,

pub fn create(allocator: Allocator) !Cpu {
    return Cpu{
        .ime_scheduled = false,
        .mem = try Memory.create(allocator),
        .regs = Registers.init(),
    };
}
pub fn deinit(cpu: Cpu, allocator: Allocator) void {
    allocator.destroy(cpu.mem);
}

pub fn execNextInstruction(cpu: *Cpu) usize {
    if (cpu.regs.get("PC") == 0xC243) @breakpoint();
    const ime_was_scheduled = cpu.ime_scheduled;
    const opcode = cpu.nextByte();
    const cycles =  instructions.exec(cpu, opcode);
    if (ime_was_scheduled) {
        cpu.ime_scheduled = false;
        cpu.regs.ime = true;
    }
    return cycles;
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


pub fn pushBytes(cpu: *Cpu, bytes: u16) void {
    std.log.debug("PUSH", .{});
    cpu.regs.set("SP", cpu.regs.get("SP") -% 2);
    const addr = cpu.regs.get("SP");
    cpu.mem.writeBytes(addr, bytes);
}

pub fn peakByte(cpu: *Cpu) u8 {
    return cpu.mem.readByte(cpu.regs.pc);
}

pub fn peakSignedByte(cpu: *Cpu) i8 {
    return @bitCast(cpu.mem.readByte(cpu.regs.pc));
}
pub fn peakBytes(cpu: *Cpu) u16 {
    return cpu.mem.readBytes(cpu.regs.pc);
}

pub fn popBytes(cpu: *Cpu) u16 {
    std.log.debug("POP", .{});
    const data = cpu.mem.readBytes(cpu.regs.get("SP"));
    cpu.regs.set("SP", cpu.regs.get("SP") +% 2);
    return data;
}

test "pushing/popping" {
    const t = std.testing;
    var cpu = try Cpu.create(t.allocator);
    defer cpu.deinit(t.allocator);

    const start = cpu.regs.get("SP");

    cpu.pushBytes(0x1234);
    cpu.pushBytes(0xAABB);
    cpu.pushBytes(0xAAAA);
    cpu.pushBytes(0xAACC);

    try t.expectEqual(cpu.popBytes(), 0xAACC);
    try t.expectEqual(cpu.popBytes(), 0xAAAA);
    try t.expectEqual(cpu.popBytes(), 0xAABB);
    try t.expectEqual(cpu.popBytes(), 0x1234);

    try t.expect(cpu.regs.get("SP") == start);
}

test "combined registers" {
    const t = std.testing;
    var regs = Registers.init();
    regs.set("B", 0b00100100);
    regs.set("C", 0b01110001);
    const combined: u16 = 0b00100100_01110001;
    try t.expectEqual(combined, regs.get("BC"));
}

pub fn jp(cpu: *Cpu, addr: u16) void {
    cpu.regs.pc = addr;
}
pub fn call(cpu: *Cpu, addr: u16) void {
    cpu.pushBytes(cpu.regs.get("PC"));
    cpu.jp(addr);
}
pub fn xor(cpu: *Cpu, n: u8) void {
    cpu.regs.set("A", cpu.regs.get("A") ^ n);
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(false);
}
pub fn or_(cpu: *Cpu, n: u8) void {
    cpu.regs.set("A", cpu.regs.get("A") | n);
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(false);
}

pub fn and_(cpu: *Cpu, n: u8) void {
    cpu.regs.set("A", cpu.regs.get("A") & n);
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(false);
}
pub fn add(cpu: *Cpu, n: u8) void {
    const a = cpu.regs.get("A");
    cpu.regs.set("A", n +% a);
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(addHalfCarry8(a, n));
    cpu.regs.set_c(a > cpu.regs.get("A"));
}
pub fn add16(cpu: *Cpu, n: u16) void {
    const hl = cpu.regs.get("HL");
    const res = n +% hl;
    cpu.regs.set("HL", res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(addHalfCarry16(hl, n));
    cpu.regs.set_c(hl > res);
}
pub fn adc(cpu: *Cpu, n: u8) void {
    const c = @intFromBool(cpu.regs.get_c());
    const a = cpu.regs.get("A");
    cpu.regs.set("A", a +% n +% c);
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(addHalfCarry8(a, a +% c));
    cpu.regs.set_c(a > cpu.regs.get("A"));
}
pub fn sbc(cpu: *Cpu, n: u8) void {
    const c = @intFromBool(cpu.regs.get_c());
    const a = cpu.regs.get("A");
    cpu.regs.set("A", a -% n -% c);
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(addHalfCarry8(a, n -% c));
    cpu.regs.set_c(a < cpu.regs.get("A"));
}

pub fn addHalfCarry8(a: u8, b: u8) bool {
    const la = a & 0x0F;
    const lb = b & 0x0F;
    const mask = 0x01 << 4;
    return (la + lb) & mask == mask;
}
pub fn subHalfCarry8(a: u8, b: u8) bool {
    return (a & 0x0F) < (b & 0x0F);
}
pub fn addHalfCarry16(a: u16, b: u16) bool {
    const la = a & 0x0FFF;
    const lb = b & 0x0FFF;
    const mask = 0x01 << 4;
    return (la + lb) & mask == mask;
}
pub fn subHalfCarry16(a: u16, b: u16) bool {
    return (a & 0x0FFF) < (b & 0x0FFF);
}

pub fn dec(cpu: *Cpu, comptime s: []const u8) void {
    const r = cpu.regs.get(s);
    cpu.regs.set(s, r -% 1);
    cpu.regs.set_z(cpu.regs.get(s) == 0);
    cpu.regs.set_n(true);
    cpu.regs.set_h(subHalfCarry8(r, 1));
}

pub fn inc(cpu: *Cpu, comptime s: []const u8) void {
    const r = cpu.regs.get(s);
    cpu.regs.set(s, r +% 1);
    cpu.regs.set_z(cpu.regs.get(s) == 0);
    cpu.regs.set_n(true);
    cpu.regs.set_h(addHalfCarry8(r, 1));
}

pub fn rr(cpu: *Cpu, comptime s: []const u8) void {
   const val = cpu.regs.get(s);

    const c: u8 = @intFromBool(cpu.regs.get_c());
    const old_b0 = val & 0x01;

    const shifted = val >> 1;
    const res = shifted | (c << 7);
    cpu.regs.set(s, shifted | (c << 7));

    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(old_b0 == 1);
}

pub fn sub(cpu: *Cpu, val: u8) void {
    const a = cpu.regs.get("A");
    cpu.regs.set("A", a -% val);
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(true);
    cpu.regs.set_h(subHalfCarry8(a, val));
    cpu.regs.set_c(a > cpu.regs.get("A"));
}

pub fn cp(cpu: *Cpu, val: u8) void {
    const a = cpu.regs.get("A");
    cpu.regs.set_z(a == val);
    cpu.regs.set_n(true);
    cpu.regs.set_c(a < val);
    cpu.regs.set_h(subHalfCarry8(a, val));
}

pub fn srl(cpu: *Cpu, comptime s: []const u8) void {
    const v = cpu.regs.get(s);
    cpu.regs.set(s, v << 1);
}
