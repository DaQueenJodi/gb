const std = @import("std");
const Memory = @import("Memory.zig");
const assert = std.debug.assert;


const Ppu = @This();


const SCREEN_W = 160;
const SCREEN_H = 144;


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

next_sprite: ?FoundSprite = null,
// sprites start transparent so it shouldnt be rendered :)
sprite_tile_low: u8 = 0x00,
sprite_tile_high: u8 = 0x00,
sprite_tile_idx: u3 = 0,
bg_tile_low: u8 = undefined,
bg_tile_high: u8 = undefined,
// so that bg_tile is fetched
bg_tile_idx: u3 = undefined,

just_finished: bool = false,
last_stat_line: bool = false,
pixel_x: u8 = 0,
found_sprites: std.BoundedArray(FoundSprite, 10) = .{},
oam_index: u8 = 0,
scanline_dots: u16 = 0,
mode3_penalties: u8 = 0,
wy_condition: bool = false,
inside_window: bool = false,
window_line_counter: u8 = 0,

const colors = [_]u8{0xFF, 0xA9, 0x54, 0x00};
pub var FB: [SCREEN_H*SCREEN_W]u8 = undefined;

pub fn tick(ppu: *Ppu, mem: *Memory) void {

    mem.io.STAT.lyc_eq_ly = mem.io.LY == mem.io.LYC;

    switch (mem.io.STAT.ppu_mode) {
        .oam_scan => {
            if (mem.io.LY == mem.io.WY) ppu.wy_condition = true;

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


                    // sorted to make sure theyre displayed in the right order
                    // sorts descendingly, so you can pop elements off easily
                    ppu.sortFoundSprites();
                }
            }
        },
        .drawing => {
            if (ppu.scanline_dots == 80 + 172 + ppu.mode3_penalties) {
                mem.io.STAT.ppu_mode = .hblank;
            } else {
                const ly: u16 = mem.io.LY;
                const idx = ly*SCREEN_W+ppu.pixel_x;
                if (idx < SCREEN_W*SCREEN_H) {
                    // pixel_x is incremented there
                    FB[idx] = ppu.nextPixel(mem.*);
                }
            }
        },
        .hblank => {
            if (ppu.scanline_dots == 80 + 376) {
                if (mem.io.LY == 143) {
                    mem.io.STAT.ppu_mode = .vblank;
                    mem.io.IF.vblank = true;
                } else {
                    mem.io.STAT.ppu_mode = .oam_scan;
                    ppu.wy_condition = false;
                    if (ppu.inside_window) {
                        ppu.window_line_counter += 1;
                        ppu.inside_window = false;
                    }
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
                    ppu.window_line_counter = 0;
                    ppu.just_finished = true;

                    mem.io.STAT.ppu_mode = .oam_scan;
                    ppu.wy_condition = false;
                    ppu.inside_window = false;
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

fn getBgTile(ppu: *Ppu, mem: Memory) void {
    const ly: u16 = mem.io.LY;
    const tilemap: u16 = switch (mem.io.LCDC.bg_tile_map_area) {
        0 => 0x9800,
        1 => 0x9C00
    };
    const tile_x: u16 = (@divFloor(ppu.pixel_x, 8) + @divFloor(mem.io.SCX, 8)) & 0x1F;
    assert(tile_x < 32);
    const tile_y: u16 = @divFloor((ly + mem.io.SCY) & 0xFF, 8);
    const tile_off = tile_y*32+tile_x;
    
    const tile_number: u16 = mem.readByte(tilemap + tile_off);

    const signed = mem.io.LCDC.bg_window_tile_data_area == 0;
    const tile_data: u16 = blk: {
        if (signed and tile_number < 128) break :blk 0x9000;
        break :blk 0x8000;
    };

    const off_y: u16 = @mod(ly + mem.io.SCY, 8);
    const off_x: u16 = @mod(mem.io.SCX, 8);


    const tile_addr = tile_data + tile_number*16 + 2*off_y;
    ppu.bg_tile_low =  mem.readByte(tile_addr);
    ppu.bg_tile_high =  mem.readByte(tile_addr + 1);
    ppu.bg_tile_idx = @intCast(off_x);
}


fn getSpriteTile(ppu: *Ppu, mem: Memory) void {
    // NOTE: next_sprite is gaurenteed to be the next sprite when this function is called
    if (ppu.next_sprite == null) {
        ppu.sprite_tile_idx = 0;
        ppu.sprite_tile_low = 0x00;
        ppu.sprite_tile_high = 0x00;
        return;
    }

    // TODO: off_x
    const sprite = ppu.next_sprite.?;
    const off_y: u16 = blk: {
        const y_plus_16_i: i16 = sprite.y_plus_16;
        const y_i = y_plus_16_i - 16;
        break :blk @intCast(mem.io.LY - y_i);
    };
    const off_x: u16 = blk: {
        const x_plus_8_i: i16 = sprite.x_plus_8;
        const x_i = x_plus_8_i - 8;
        break :blk @intCast(ppu.pixel_x - x_i);
    };

    const tile_index: u16 = sprite.tile_index;
    const addr: u16 = 0x8000 + 16*tile_index + 2*off_y;
    ppu.sprite_tile_low = mem.readByte(addr);
    ppu.sprite_tile_high = mem.readByte(addr+1);
    ppu.sprite_tile_idx = @intCast(off_x);
}

fn getPixelColorID(low: u8, high: u8, index: u3) u8 {
    const mask = @as(u8, 0x01) << 7 - index;
    const l: u1 = @intFromBool(low & mask == mask);
    const h: u2 = @intFromBool(high & mask == mask);
    return h << 1 | l;
}
fn nextPixel(ppu: *Ppu, mem: Memory) u8 {
    // load first tile
    if (ppu.pixel_x == 0) {
        ppu.next_sprite = ppu.found_sprites.popOrNull();
        getBgTile(ppu, mem);
    }

    if (ppu.next_sprite) |s| {
        if (ppu.pixel_x + 8 <= s.x_plus_8) {
            getSpriteTile(ppu, mem);
            ppu.next_sprite = ppu.found_sprites.popOrNull();
        }
    }


    ppu.pixel_x += 1;

    // just rendered last pixel
    if (ppu.bg_tile_idx == 7) {
        ppu.getBgTile(mem);
    } else {
        ppu.bg_tile_idx += 1;
    }
    if (ppu.sprite_tile_idx == 7) {
        ppu.sprite_tile_idx = 0;
        // fully transparent so wont be rendered
        ppu.sprite_tile_low = 0x00;
        ppu.sprite_tile_high = 0x00;
    }
    const bg_color_id = getPixelColorID(ppu.bg_tile_low, ppu.bg_tile_high, ppu.bg_tile_idx);
    return colors[mem.io.BGP.get(bg_color_id)];
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


fn cmpFoundSpriteLT(_: void, a: FoundSprite, b: FoundSprite) bool {
    return a.x_plus_8 > b.x_plus_8;
}
fn sortFoundSprites(ppu: *Ppu) void {
    std.mem.sort(FoundSprite, ppu.found_sprites.slice(), {}, cmpFoundSpriteLT);
}
