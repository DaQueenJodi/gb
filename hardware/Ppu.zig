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

pixel_x: u8,
found_sprites: std.BoundedArray(FoundSprite, 10) = .{},
oam_index: u8 = 0,
scanline_dots: u16 = 0,
mode3_penalties: u8 = 0,

const colors = [_]u8{0xFF, 0xA9, 0x54, 0x00};
const FB = [144*160]u8;


pub fn tick(ppu: *Ppu, mem: *Memory) void {
    switch (mem.io.STAT.ppu_mode) {
        .oam_scan => {
            if (ppu.oam_index < 40 and ppu.found_sprites.len < 10) {
                const attr_base_addr: u16 = 0xFE00 + 4*ppu.oam_index;
                const y = mem.readByte(attr_base_addr + 0);
                if (mem.io.LY + 16 >= y and mem.io.LY) {
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
                    mem.io.STAT.ppu_mode = .drawing;
                    ppu.pixel_x = 0;
                }
            }
        },
        .drawing => {

            FB[mem.io.LY*160+ppu.pixel_x] = ppu.nextPixel();
            
            ppu.pixel_x += 1;
            if (ppu.scanline_dots == 172 + ppu.mode3_penalties) {
                mem.io.STAT.ppu_mode = .hblank;
            }
        },
        .hblank => {
            if (ppu.scanline_dots == 204 - ppu.mode3_penalties) {
                if (mem.io.LY == 143) {
                    mem.io.STAT.ppu_mode = .vblank;
                }
                ppu.mode3_penalties = 0;
                ppu.found_sprites.len = 0;
                mem.io.LY += 1;
            }
        },
    }
}


fn nextPixel(ppu: *Ppu, mem: Memory) void {

}
