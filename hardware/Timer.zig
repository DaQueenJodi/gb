const std = @import("std");

const Memory = @import("Memory.zig");

const Timer = @This();

cycle: usize = 0,


pub fn tick(timer: *Timer, mem: *Memory) void {
    if (@mod(timer.cycle, 256) == 0) mem.io.DIV +%= 1;
    if (mem.io.TAC.enable) {
        const cycles_needed = @divExact(mem.io.TAC.getHz(), 64);
        if (@mod(timer.cycle, cycles_needed) == 0) {
            if (mem.io.TIMA == 0xFF) {
                //mem.io.IF.timer = true;
                mem.io.TIMA = mem.io.TMA;
            } else {
                mem.io.TIMA += 1;
            }
        }
    }

    timer.cycle += 1;
}
