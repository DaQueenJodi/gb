const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Memory = @import("../Memory.zig");
const Input = @import("../Input.zig");
const Cart = @import("Cart.zig");

const RomOnly = @This();

const KiB = 1024;

extra_rom: [16*KiB]u8,

pub fn memory(self: *RomOnly, allocator: Allocator, input: *const Input) !*Memory {
    return Memory.create(allocator, input, .{
        .ctx = self,
        .read_ram = readStub,
        .write_ram = writeStub,
        .read_bank1 = readBank1,
        .write_bank0 = writeStub,
        .write_bank1 = writeStub,
    });
}

pub fn create(allocator: Allocator, cart: Cart) !*RomOnly {
    const rom_only = try allocator.create(RomOnly);
    @memcpy(rom_only.extra_rom[0..], cart.cart_mem[16*KiB..]);
    return rom_only;
}

fn readStub(_: *anyopaque, _: u16) u8 {
    return 0xFF;
}

fn writeStub(_: *anyopaque, _: u16, _: u8) void {
    return;
}

fn readBank1(ctx: *anyopaque, addr: u16) u8 {
    const self: *RomOnly = @ptrCast(ctx);
    
    assert(addr >= 0x4000 and addr <= 0x7FFF);
    return self.extra_rom[addr - 0x4000];
}
