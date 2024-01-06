const std = @import("std");

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
    ROM_MBC1 = 0x1,
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
    return .{
        .flavor = @enumFromInt(cartridge_flavor_byte),
        .name = name_start[0..name_len],
        .rom_size = romSizeFromByte(rom_size_byte),
        .ram_size = ramSizeFromByte(ram_size_byte),
        .is_japanese = cart[DEST_CODE] == 0,
    };
}
