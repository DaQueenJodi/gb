const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Registers = @import("Registers.zig");
const Memory = @import("Memory.zig");

const Cpu = @This();

const CpuMode = enum { halt, stop, normal };

mode: CpuMode = .normal,
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

pub fn handleInterupts(cpu: *Cpu) bool {
    if (!cpu.regs.ime) return false;
    const IF: u8 = @bitCast(cpu.mem.io.IF);
    const IE: u8 = @bitCast(cpu.mem.ie);
    const allowed_interupts = IF & IE;
    const n = @ctz(allowed_interupts);
    const addr: u16 = switch (n) {
        // VBLANK
        0 => 0x40,
        // LCD (STAT)
        1 => 0x48,
        // TIMER
        2 => 0x50,
        // Serial
        3 => 0x58,
        // Joypad
        4 => 0x60,
        else => return false,
    };

    const ns: u3 = @intCast(n);
    cpu.mem.io.IF = @bitCast(IF & ~(@as(u8, 0x01) << ns));
    cpu.regs.ime = false;
    cpu.call(addr);

    return true;
}

pub fn nextByte(cpu: *Cpu) u8 {
    const b = cpu.mem.readByte(cpu.regs.pc);
    cpu.regs.pc +%= 1;
    return b;
}

pub fn nextSignedByte(cpu: *Cpu) i8 {
    const b: i8 = @bitCast(cpu.mem.readByte(cpu.regs.pc));
    cpu.regs.pc +%= 1;
    return b;
}
pub fn nextBytes(cpu: *Cpu) u16 {
    const bs = cpu.mem.readBytes(cpu.regs.pc);
    cpu.regs.pc +%= 2;
    return bs;
}

pub fn pushBytes(cpu: *Cpu, bytes: u16) void {
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
    cpu.regs.set_h(true);
    cpu.regs.set_c(false);
}
pub fn add(cpu: *Cpu, n: u8) void {
    const a = cpu.regs.get("A");
    cpu.regs.set("A", a +% n);
    cpu.regs.set_z(cpu.regs.get("A") == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(addHalfCarry8(a, n));
    cpu.regs.set_c(a > cpu.regs.get("A"));
}
pub fn add16(cpu: *Cpu, n: u16) void {
    const hl = cpu.regs.get("HL");
    const res = n +% hl;
    cpu.regs.set("HL", res);
    cpu.regs.set_n(false);
    cpu.regs.set_h(addHalfCarry16(hl, n));
    cpu.regs.set_c(hl > res);
}
pub fn adc(cpu: *Cpu, n: u8) void {
    const c = @intFromBool(cpu.regs.get_c());
    const a = cpu.regs.get("A");
    const summand = n +% c;
    const res = a +% summand;
    cpu.regs.set("A", res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    const hc = ((a & 0x0F) + (n & 0x0F) + (c)) > 0xF;
    cpu.regs.set_h(hc);
    cpu.regs.set_c(a > res or n > summand);
}
pub fn sbc(cpu: *Cpu, n: u8) void {
    const c = @intFromBool(cpu.regs.get_c());
    const a = cpu.regs.get("A");
    const subtrahend = n +% c;
    const res = a -% subtrahend;
    cpu.regs.set("A", res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(true);
    const hc = (a & 0x0F) < ((n & 0x0F) + (c));
    cpu.regs.set_h(hc);
    cpu.regs.set_c(a < res or n > subtrahend);
}

pub fn addHalfCarry8(a: u8, b: u8) bool {
    const la = a & 0x0F;
    const lb = b & 0x0F;
    const mask = 0x01 << 4;
    return (la + lb) & mask == mask;
}
pub fn addHalfCarry16(a: u16, b: u16) bool {
    const la = a & 0x0FFF;
    const lb = b & 0x0FFF;
    const mask = 0x01 << 12;
    return (la + lb) & mask == mask;
}
pub fn subHalfCarry8(a: u8, b: u8) bool {
    return (a & 0x0F) < (b & 0x0F);
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
    cpu.regs.set_n(false);
    cpu.regs.set_h(addHalfCarry8(r, 1));
}

pub fn rr(cpu: *Cpu, comptime s: []const u8) void {
    const val = cpu.regs.get(s);

    const c: u8 = @intFromBool(cpu.regs.get_c());
    const old_b0 = val & 0x01;

    const shifted = val >> 1;
    const res = shifted | (c << 7);
    cpu.regs.set(s, res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(old_b0 == 1);
}

pub fn rl(cpu: *Cpu, comptime s: []const u8) void {
    const val = cpu.regs.get(s);

    const c: u8 = @intFromBool(cpu.regs.get_c());
    const old_b7 = (val & (0x01 << 7)) >> 7;

    const shifted = val << 1;
    const res = shifted | c;
    cpu.regs.set(s, res);

    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(old_b7 == 1);
}
pub fn rlc(cpu: *Cpu, comptime s: []const u8) void {
    const orig = cpu.regs.get(s);
    const masked: u8 = orig & (0x01 << 7);
    const b7: u1 = @intCast(masked >> 7);
    const shifted = orig << 1;
    const res = (shifted | b7);
    cpu.regs.set(s, res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(b7 == 1);
}

pub fn rrc(cpu: *Cpu, comptime s: []const u8) void {
    const orig = cpu.regs.get(s);
    const b0: u8 = @intCast(orig & 0x01);
    const shifted = orig >> 1;
    const res = (shifted | (b0 << 7));
    cpu.regs.set(s, res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(b0 == 1);
}
pub fn sla(cpu: *Cpu, comptime s: []const u8) void {
    const orig = cpu.regs.get(s);
    const old_b7 = (orig & (0x01 << 7)) >> 7;
    const res = orig << 1;
    cpu.regs.set(s, res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(old_b7 == 1);
}
pub fn sra(cpu: *Cpu, comptime s: []const u8) void {
    const orig = cpu.regs.get(s);
    const old_b0 = orig & 0x01;
    const old_b7 = orig & (0x01 << 7);
    const res = (orig >> 1) | old_b7;
    cpu.regs.set(s, res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(old_b0 == 1);
}
pub fn swap(cpu: *Cpu, comptime s: []const u8) void {
    const orig = cpu.regs.get(s);
    const h = (orig & 0xF0) >> 4;
    const l = orig & 0x0F;
    const res = (l << 4) | h;
    cpu.regs.set(s, res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(false);
}
pub fn sub(cpu: *Cpu, val: u8) void {
    const a = cpu.regs.get("A");
    const res = a -% val;
    cpu.regs.set("A", res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(true);
    cpu.regs.set_h(subHalfCarry8(a, val));
    cpu.regs.set_c(a < res);
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
    const old_b0 = v & 0x01;
    const res = v >> 1;
    cpu.regs.set(s, res);
    cpu.regs.set_z(res == 0);
    cpu.regs.set_n(false);
    cpu.regs.set_h(false);
    cpu.regs.set_c(old_b0 == 1);
}
pub fn bit(cpu: *Cpu, v: u8, n: u3) void {
    const mask = @as(u8, 0x01) << n;
    const b = (v & mask) == mask;
    cpu.regs.set_z(!b);
    cpu.regs.set_n(false);
    cpu.regs.set_h(true);
}
