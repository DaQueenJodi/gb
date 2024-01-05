const std = @import("std");
const Memory = @import("Memory.zig");
const assert = std.debug.assert;


const Ppu = @This();


const SpriteAttributes = packed struct {
    _cgb_stuff_i_dont_care_about: u4,
    palette: u1,
    xflip: bool,
    yflip: bool,
    priority: u1
};

const FoundSprite = struct {
    x_plus_8: u8,
    y_plus_16: u8,
    tile_index: u8,
    attrs: SpriteAttributes,
};

just_finished: bool = false,
last_stat_line: bool = false,
pixel_x: u8 = 0,
found_sprites: std.BoundedArray(FoundSprite, 10) = .{},
oam_index: u8 = 0,
scanline_dots: u16 = 0,
mode3_penalties: u8 = 0,

const colors = [_]u8{0xFF, 0xA9, 0x54, 0x00};
pub var FB: [144*160]u8 = undefined;


pub fn tick(ppu: *Ppu, mem: *Memory) void {
    switch (mem.io.STAT.ppu_mode) {
        .oam_scan => {
            if (ppu.oam_index < 40 and ppu.found_sprites.len < 10) {
                const oam_index: u16 = ppu.oam_index;
                const attr_base_addr: u16 = 0xFE00 + 4*oam_index;
                const y = mem.readByte(attr_base_addr + 0);
                const big = mem.io.LCDC.obj_size == 1;
                const max_off: u8 = if (big) 16 else 8;
                if (mem.io.LY + 16 >= y and mem.io.LY + 16 - max_off <= y) {
                    const x = mem.readByte(attr_base_addr + 1);
                    const idx = mem.readByte(attr_base_addr + 2);
                    const attrs: SpriteAttributes = @bitCast(mem.readByte(attr_base_addr + 3));

                    ppu.found_sprites.append(.{
                        .attrs = attrs,
                        .x_plus_8 = x,
                        .y_plus_16 = y,
                        .tile_index = idx,
                    }) catch unreachable;

                    ppu.oam_index += 1;
                }
                if (ppu.scanline_dots == 80) {
                    ppu.mode3_penalties = 0;
                    mem.io.STAT.ppu_mode = .drawing;
                    ppu.pixel_x = 0;
                }
            }
        },
        .drawing => {
            ppu.pixel_x += 1;
            if (ppu.scanline_dots == 80 + 172 + ppu.mode3_penalties) {
                mem.io.STAT.ppu_mode = .hblank;
            } else {
                const ly: u16 = mem.io.LY;
                const idx = ly*160+ppu.pixel_x;
                if (idx < 160*144) {
                    FB[idx] = ppu.nextPixel(mem.*);
                }
            }
        },
        .hblank => {
            if (ppu.scanline_dots == 80 + 376) {
                if (mem.io.LY == 143) {
                    mem.io.STAT.ppu_mode = .vblank;
                } else {
                    mem.io.STAT.ppu_mode = .oam_scan;
                    ppu.found_sprites.len = 0;
                }
                ppu.scanline_dots = 0;
                mem.io.LY += 1;
            }
        },
        .vblank => {
            if (ppu.scanline_dots == 456) {
                if (mem.io.LY == 153) {
                    mem.io.LY = 0;
                    ppu.just_finished = true;

                    mem.io.STAT.ppu_mode = .oam_scan;
                    ppu.found_sprites.len = 0;
                } else {
                    mem.io.LY += 1;
                }
                ppu.scanline_dots = 0;
            }
        }
    }
    ppu.scanline_dots += 1;
}


fn nextPixel(ppu: *Ppu, mem: Memory) u8 {
    _ = ppu;
    _ = mem;
    return 0xAB;
}



pub fn handleLCDInterrupts(ppu: *Ppu, mem: *Memory) void {
    const stat = mem.io.STAT;
    const new_stat_line =
    (stat.mode_0_select and stat.ppu_mode == .hblank) or
    (stat.mode_1_select and stat.ppu_mode == .vblank) or
    (stat.mode_2_select and stat.ppu_mode == .oam_scan) or
    (stat.lyc_select and stat.lyc_eq_ly);

    if (new_stat_line and !ppu.last_stat_line) mem.io.IF.stat = true;
    ppu.last_stat_line = new_stat_line;
}
