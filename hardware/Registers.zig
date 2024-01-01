const std = @import("std");

const Registers = @This();

pub const FlagRegister = packed struct {
    _padding: u4,
    c: bool,
    h: bool,
    n: bool,
    z: bool,
};

const PackedReg = packed struct { b: u8, a: u8 };

af: PackedReg,
bc: PackedReg,
de: PackedReg,
hl: PackedReg,
sp: u16,
pc: u16,
ime: bool,
pub fn init__() Registers {
    var regs: Registers = undefined;
    regs.set("PC", 0x00);
    regs.ime = false;
    return regs;
}
pub fn init() Registers {
    var regs: Registers = undefined;
    regs.set("PC", 0x0100);
    regs.set("AF", 0x0001);
    regs.set("F", 0xB0);
    regs.set("BC", 0x0013);
    regs.set("DE", 0x00D8);
    regs.set("HL", 0x014D);
    regs.set("SP", 0xFFFE);
    regs.ime = false;
    return regs;
}
pub fn get_z(self: *Registers) bool {
    const f: *FlagRegister = @ptrCast(&self.af.b);
    return f.z;
}
pub fn get_n(self: *Registers) bool {
    const f: *FlagRegister = @ptrCast(&self.af.b);
    return f.n;
}
pub fn get_h(self: *Registers) bool {
    const f: *FlagRegister = @ptrCast(&self.af.b);
    return f.h;
}
pub fn get_c(self: *Registers) bool {
    const f: *FlagRegister = @ptrCast(&self.af.b);
    return f.c;
}
pub fn set_z(self: *Registers, v: bool) void {
    const f: *FlagRegister = @ptrCast(&self.af.b);
    f.z = v;
}
pub fn set_n(self: *Registers, v: bool) void {
    const f: *FlagRegister = @ptrCast(&self.af.b);
    f.n = v;
}
pub fn set_h(self: *Registers, v: bool) void {
    const f: *FlagRegister = @ptrCast(&self.af.b);
    f.h = v;
}
pub fn set_c(self: *Registers, v: bool) void {
    const f: *FlagRegister = @ptrCast(&self.af.b);
    f.c = v;
}
fn assertIsUpper(comptime s: []const u8) void {
    comptime {
        for (s) |c| {
            if (!std.ascii.isUpper(c)) @compileError("s must be all uppercase letters!");
        }
    }
}
fn getType(comptime s: []const u8) type {
    return switch (s.len) {
        1 => u8,
        2 => u16,
        else => @compileError("s must be either length 1 or 2"),
    };
}
pub fn get(self: Registers, comptime s: []const u8) getType(s) {
    assertIsUpper(s);
    switch (s.len) {
        1 => {
            switch (s[0]) {
                'A' => return self.af.a,
                'F' => return self.af.b,
                'B' => return self.bc.a,
                'C' => return self.bc.b,
                'D' => return self.de.a,
                'E' => return self.de.b,
                'H' => return self.hl.a,
                'L' => return self.hl.b,
                else => @compileError(std.fmt.comptimePrint("invalid u8 register s: {s}", .{s})),
            }
        },
        2 => {
            if (comptime streql(s, "AF")) {
                return @bitCast(self.af);
            } else if (comptime streql(s, "BC")) {
                return @bitCast(self.bc);
            } else if (comptime streql(s, "DE")) {
                return @bitCast(self.de);
            } else if (comptime streql(s, "HL")) {
                return @bitCast(self.hl);
            } else if (comptime streql(s, "PC")) {
                return self.pc;
            } else if (comptime streql(s, "SP")) {
                return self.sp;
            } else @compileError(std.fmt.comptimePrint("invalid u16 register s: {s}", .{s}));
        },
        else => unreachable,
    }
}
pub fn set(self: *Registers, comptime s: []const u8, val: anytype) void {
    assertIsUpper(s);
    switch (s.len) {
        1 => {
            const v: u8 = val;
            switch (s[0]) {
                'A' => self.af.a = v,
                'F' => self.af.b = v,
                'B' => self.bc.a = v,
                'C' => self.bc.b = v,
                'D' => self.de.a = v,
                'E' => self.de.b = v,
                'H' => self.hl.a = v,
                'L' => self.hl.b = v,
                else => @compileError(std.fmt.comptimePrint("invalid u8 register s: {s}", .{s})),
            }
        },
        2 => {
            const v: u16 = val;
            if (comptime streql(s, "AF")) {
                self.af = @bitCast(v);
            } else if (comptime streql(s, "BC")) {
                self.bc = @bitCast(v);
            } else if (comptime streql(s, "DE")) {
                self.de = @bitCast(v);
            } else if (comptime streql(s, "HL")) {
                self.hl = @bitCast(v);
            } else if (comptime streql(s, "SP")) {
                self.sp = @bitCast(v);
            } else if (comptime streql(s, "PC")) {
                self.pc = @bitCast(v);
            } else @compileError(std.fmt.comptimePrint("invalid u16 register s: {s}", .{s}));
        },
        else => @compileError("length of s must be either 1 or 2"),
    }
}
fn streql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
