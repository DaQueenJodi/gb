const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Cart = @import("Cart.zig");
const Input = @import("../Input.zig");
const Memory = @import("../Memory.zig");

const KiB = 1024;

const Mbc1 = @This();

extra_rom: []const u8,
rom_size: usize,
ram: []u8,
ram_size: usize,
ram_enabled: bool = false,
rom_bank_number: u5 = 0x00,
// OR upper bits of rom bank number
ram_bank_number: u2 = 0x00,
banking_mode_select: enum (u1) {
    simple = 0b0,
    advanced = 0b1
} = .simple,



pub fn create(allocator: Allocator, cart: Cart) !*Mbc1 {
    const mbc1 = try allocator.create(Mbc1);
    mbc1.* = .{
        .rom_size = cart.rom_size,
        .ram_size = cart.ram_size,
        .ram = try allocator.alloc(u8, cart.ram_size),
        .extra_rom = try allocator.alloc(u8, cart.rom_size - 16*KiB),
    };
    @memcpy(@constCast(mbc1.extra_rom[0..]), cart.cart_mem[16*KiB..]);
    return mbc1;
}

pub fn deinit(self: Mbc1, allocator: Allocator) void {
    allocator.free(self.extra_rom);
    allocator.free(self.ram);
}

pub fn memory(self: *Mbc1, allocator: Allocator, input: *const Input) !*Memory {
    return try Memory.create(allocator, input, .{
        .ctx = self,
        .write_bank0 = bank0WriteByte,
        .read_bank1 = bank1ReadByte,
        .write_bank1 = bank1WriteByte,
        .write_ram = ramWriteByte,
        .read_ram = ramReadByte,
    });
}


fn bank0WriteByte(ctx: *anyopaque, addr: u16, val: u8) void {
    const self: *Mbc1 = @alignCast(@ptrCast(ctx));

    switch (addr) {
        0x0...0x1FFF => self.ram_enabled = val & 0x0F == 0xA,
        // TODO: mask if number is too large
        0x2000...0x3FFF => self.rom_bank_number = @intCast(val & 0b11111),
        else => unreachable,
    }
}

fn bank1WriteByte(ctx: *anyopaque, addr: u16, val: u8) void {
    const self: *Mbc1 = @alignCast(@ptrCast(ctx));

    switch (addr) {
        0x4000...0x5FFF => self.ram_bank_number = @intCast(val & 0b11),
        0x6000...0x7FFF => self.banking_mode_select = @enumFromInt(val  & 0b1),
        else => unreachable,
    }
}

fn ramWriteByte(ctx: *anyopaque, addr: u16, val: u8) void {
    const self: *Mbc1 = @alignCast(@ptrCast(ctx));

    assert(addr >= 0xA000 and addr <= 0xBFFF);
    if (!self.ram_enabled) return;

    const real_addr: usize = switch (self.banking_mode_select) {
        .simple => addr,
        .advanced => blk: {
            const ram_bank_number: usize = self.ram_bank_number;
            break :blk addr+(8*KiB*ram_bank_number);
        },
    };
    self.ram[real_addr - 0xA000] = val; 
}
fn ramReadByte(ctx: *anyopaque, addr: u16) u8 {
    const self: *Mbc1 = @alignCast(@ptrCast(ctx));

    assert(addr >= 0xA000 and addr <= 0xBFFF);
    if (!self.ram_enabled) return 0xFF;

    const real_addr: usize = switch (self.banking_mode_select) {
        .simple => addr,
        .advanced => blk: {
            const ram_bank_number: usize = self.ram_bank_number;
            break :blk addr+(8*KiB*ram_bank_number);
        },
    };
    return self.ram[real_addr - 0xA000]; 
}

fn bank1ReadByte(ctx: *anyopaque, addr: u16) u8 {
    const self: *Mbc1 = @alignCast(@ptrCast(ctx));

    assert(addr >= 0x4000 and addr <= 0x7FFF);
    const rom_bank_number: usize = blk: {
        const bank_number = if (self.rom_bank_number == 0) 1 else self.rom_bank_number;
        // since we technically start in bank1
        break :blk bank_number - 1;
    };
    const real_addr: usize = addr+(16*KiB*rom_bank_number);
    return self.extra_rom[real_addr - 0x4000];
}
