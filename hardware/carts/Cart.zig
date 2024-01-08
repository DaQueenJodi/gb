const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Input = @import("../Input.zig");
const Memory = @import("../Memory.zig");

const Mbc1 = @import("Mbc1.zig");
const RomOnly = @import("RomOnly.zig");

const Cart = @This();

const CART_START = 0x0100;
const NINTENDO_GRAPHIC = 0x104;
const GAME_TITLE = 0x134;
const CARTRIDGE_FLAVOR = 0x0147;
const ROM_SIZE = 0x0148;
const RAM_SIZE = 0x0149;
const DEST_CODE = 0x014A;

const CartridgeFlavor = enum(u8) {
    ROM_ONLY = 0x0,
    MBC1 = 0x01,
    MBC1_RAM= 0x02,
    MBC1_RAM_BATTERY = 0x03,
};

const KiB = 1024;
const MiB = KiB * 1024;
fn ramSizeFromByte(b: u8) usize {
    return switch (b) {
        0 => 0,
        1 => 2 * KiB,
        2 => 8 * KiB,
        3 => 32 * KiB,
        4 => 128 * KiB,
        else => std.debug.panic("invalid byte: {}", .{b}),
    };
}
fn romSizeFromByte(b: u8) usize {
    return switch (b) {
        0 => 32 * KiB,
        1 => 64 * KiB,
        2 => 128 * KiB,
        3 => 256 * KiB,
        4 => 512 * KiB,
        5 => 1 * MiB,
        6 => 2 * MiB,
        else => std.debug.panic("invalid byte: {}", .{b}),
    };
}

flavor: CartridgeFlavor,
name: []const u8,
is_japanese: bool,
/// size in bytes
rom_size: usize,
ram_size: usize,
cart_mem: []const u8,
pub fn init(cart: []const u8) Cart {
    const cartridge_flavor_byte = cart[CARTRIDGE_FLAVOR];
    const rom_size_byte = cart[ROM_SIZE];
    const ram_size_byte = cart[ROM_SIZE];
    const name_start = cart[GAME_TITLE..];
    const name_len = blk: {
        for (name_start[0..16], 0..) |c, i| {
            if (c == 0) break :blk i;
        }
        break :blk 16;
    };
    std.log.err("flavor: {}", .{cartridge_flavor_byte});
    const flavor: CartridgeFlavor = @enumFromInt(cartridge_flavor_byte);
    const ram_size = blk: {
        const ram_size = ramSizeFromByte(ram_size_byte);
        if (ram_size == 0 and (flavor == .MBC1_RAM_BATTERY or flavor == .MBC1_RAM)) {
            std.log.warn("cartridge has RAM attachment but reports RAM size as 0", .{});
            break :blk 4*8*KiB;
        }
        break :blk ram_size;
    };
    return .{
        .cart_mem = cart,
        .flavor = flavor,
        .name = name_start[0..name_len],
        .rom_size = romSizeFromByte(rom_size_byte),
        .ram_size = ram_size,
        .is_japanese = cart[DEST_CODE] == 0,
    };
}

pub fn memory(cart: Cart, allocator: Allocator, input: *const Input) !*Memory {
    // NOTE: don't need to free since allocator is always an arena :p
    switch (cart.flavor) {
        .MBC1, .MBC1_RAM, .MBC1_RAM_BATTERY => {
            const mapper = try Mbc1.create(allocator, cart);
            return try mapper.memory(allocator, input);
        },
        .ROM_ONLY => {
            const mapper = try RomOnly.create(allocator, cart);
            return try mapper.memory(allocator, input);
        },
    }

}
