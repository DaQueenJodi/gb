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
    // TODO: HALT bug
    // TODO: STOP
    if (false and cpu.mode == .halt) {
        const IE: u8 = @bitCast(cpu.mem.ie);
        const IF: u8 = @bitCast(cpu.mem.io.IF);
        if (IE & IF > 0) cpu.mode = .normal;
        return 1;
    }

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
