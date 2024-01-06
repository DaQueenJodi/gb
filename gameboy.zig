const std = @import("std");

const HW = @import("hardware");
pub const Cpu = HW.Cpu;
pub const Ppu = HW.Ppu;
pub const Memory = HW.Memory;
pub const Cart = HW.Cart;
pub const Registers = HW.Registers;
pub const Timer = HW.Timer;
pub const Input = HW.Input;
pub const instructions = @import("instructions");

pub fn execNextInstruction(cpu: *Cpu) usize {
    const ime_was_scheduled = cpu.ime_scheduled;
    const opcode = cpu.nextByte();
    const cycles = instructions.exec(cpu, opcode);
    if (ime_was_scheduled) {
        std.log.info("ime was scheduled", .{});
        cpu.ime_scheduled = false;
        cpu.regs.ime = true;
    }
    return cycles;
}
