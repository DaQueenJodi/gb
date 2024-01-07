const std = @import("std");
const Memory = @import("Memory.zig");
const assert = std.debug.assert;

const Ppu = @This();

const SCREEN_W = 160;
const SCREEN_H = 144;

const SpriteAttributes = packed struct { _cgb_stuff_i_dont_care_about: u4, palette: u1, xflip: bool, yflip: bool, priority: u1, };

const FoundSprite = struct {
    x_plus_8: u8,
    y_plus_16: u8,
    tile_index: u8,
    // only used in sorting
    oam_index: u8,
    attrs: SpriteAttributes,
};

window_start_x: u8 = undefined,
next_sprite: ?FoundSprite = null,
current_sprite_attrs: ?SpriteAttributes = null,
sprite_tile_low: u8 = undefined,
sprite_tile_high: u8 = undefined,
sprite_tile_idx: u3 = undefined,
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

const colors = [_]u8{ 0xFF, 0xA9, 0x54, 0x00 };
// store three RGB values
pub var FB: [SCREEN_H * SCREEN_W * 3]u8 = undefined;

pub fn tick(ppu: *Ppu, mem: *Memory) void {
    if (!mem.io.LCDC.lcd_ppu_enable) return;
    mem.io.STAT.lyc_eq_ly = mem.io.LY == mem.io.LYC;

    switch (mem.io.STAT.ppu_mode) {
        .oam_scan => {
            if (mem.io.LY >= mem.io.WY and mem.io.LCDC.window_enable) ppu.wy_condition = true;

            if (ppu.oam_index < 40 and ppu.found_sprites.len < 10) {
                const oam_index: u16 = ppu.oam_index;
                const attr_base_addr: u16 = 0xFE00 + 4 * oam_index;
                const y = mem.readByte(attr_base_addr + 0);
                const big = mem.io.LCDC.obj_size == 1;
                const max_off: u8 = if (big) 16 else 8;
                if (mem.io.LY + 16 >= y and mem.io.LY + 16 - max_off < y) {
                    const x = mem.readByte(attr_base_addr + 1);
                    const idx = mem.readByte(attr_base_addr + 2);
                    const attrs: SpriteAttributes = @bitCast(mem.readByte(attr_base_addr + 3));

                    ppu.found_sprites.append(.{ .attrs = attrs, .x_plus_8 = x, .y_plus_16 = y, .tile_index = idx, .oam_index = ppu.oam_index }) catch unreachable;
                }
                ppu.oam_index += 1;
            }
            if (ppu.scanline_dots == 80) {
                ppu.sortFoundSprites();
                ppu.mode3_penalties = 0;
                mem.io.STAT.ppu_mode = .drawing;
                ppu.pixel_x = 0;
                ppu.next_sprite = ppu.found_sprites.popOrNull();
                getBgTile(ppu, mem);

                // sorted to make sure theyre displayed in the right order
                // sorts descendingly, so you can pop elements off easily
            }
        },
        .drawing => {
            const ly: u32 = mem.io.LY;
            const idx: u32 = (ly * SCREEN_W + ppu.pixel_x) * 3;
            if (idx < FB.len) {
                // pixel_x is incremented there
                const px = ppu.nextPixel(mem);
                FB[idx] = px;
                FB[idx + 1] = px;
                FB[idx + 2] = px;
            }
            if (ppu.wy_condition and ppu.pixel_x + 7 == mem.io.WX and mem.io.WX > 7 and mem.io.WX < 166) {
                ppu.window_start_x = ppu.pixel_x;
                ppu.inside_window = true;
                ppu.getBgTile(mem);
            }
            if (ppu.scanline_dots == 80 + 172 + ppu.mode3_penalties) {
                mem.io.STAT.ppu_mode = .hblank;
            }
        },
        .hblank => {
            if (ppu.scanline_dots == 80 + 376) {
                if (mem.io.LY == 143) {
                    mem.io.STAT.ppu_mode = .vblank;
                    mem.io.IF.vblank = true;
                } else {
                    mem.io.STAT.ppu_mode = .oam_scan;
                    ppu.oam_index = 0;
                    ppu.found_sprites.len = 0;
                    ppu.wy_condition = false;
                    if (ppu.inside_window) {
                        ppu.window_line_counter += 1;
                        ppu.inside_window = false;
                    }
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
                    ppu.oam_index = 0;
                    ppu.wy_condition = false;
                    ppu.inside_window = false;
                    ppu.found_sprites.len = 0;
                } else {
                    mem.io.LY += 1;
                }
                ppu.scanline_dots = 0;
            }
        },
    }
    ppu.scanline_dots += 1;
}

fn getWindowTile(ppu: *Ppu, mem: *const Memory) void {

    const tilemap: u16 = switch (mem.io.LCDC.window_tile_map_area) {
        0 => 0x9800,
        1 => 0x9C00,
    };

    const tile_x: u16 = @divFloor(ppu.pixel_x - ppu.window_start_x, 8);
    const tile_y: u16 = @divFloor(ppu.window_line_counter, 8);

    const tile_off = tile_y * 32 + tile_x;

    const tile_number: u16 = mem.readByte(tilemap + tile_off);
    const signed = mem.io.LCDC.bg_window_tile_data_area == 0;
    const tile_data: u16 = blk: {
        if (signed and tile_number < 128) break :blk 0x9000;
        break :blk 0x8000;
    };

    const off_y: u16 = @mod(ppu.window_line_counter, 8);
    const tile_addr = tile_data + tile_number * 16 + 2 * off_y;
    ppu.bg_tile_low = mem.readByte(tile_addr);
    ppu.bg_tile_high = mem.readByte(tile_addr + 1);
    ppu.bg_tile_idx = 0;
}
fn getBgTile(ppu: *Ppu, mem: *const Memory) void {
    if (ppu.inside_window) {
        ppu.getWindowTile(mem);
        return;
    }

    const ly: u16 = mem.io.LY;
    const tilemap: u16 = switch (mem.io.LCDC.bg_tile_map_area) {
        0 => 0x9800,
        1 => 0x9C00,
    };
    const tile_x: u16 = (@divFloor(ppu.pixel_x, 8) + @divFloor(mem.io.SCX, 8)) & 0x1F;
    assert(tile_x < 32);
    const tile_y: u16 = @divFloor((ly + mem.io.SCY) & 0xFF, 8);
    const tile_off = tile_y * 32 + tile_x;

    const tile_number: u16 = mem.readByte(tilemap + tile_off);

    const signed = mem.io.LCDC.bg_window_tile_data_area == 0;
    const tile_data: u16 = blk: {
        if (signed and tile_number < 128) break :blk 0x9000;
        break :blk 0x8000;
    };

    const off_y: u16 = @mod(ly + mem.io.SCY, 8);

    const tile_addr = tile_data + tile_number * 16 + 2 * off_y;
    ppu.bg_tile_low = mem.readByte(tile_addr);
    ppu.bg_tile_high = mem.readByte(tile_addr + 1);
    ppu.bg_tile_idx = 0;
}

fn getSpriteTile(ppu: *Ppu, mem: *const Memory) void {
    const big = mem.io.LCDC.obj_size == 1;
    // NOTE: next_sprite is gaurenteed to be the current sprite when this function is called
    const sprite = ppu.next_sprite.?;
    const off_y: u16 = blk: {
        const y_plus_16_i: i16 = sprite.y_plus_16;
        const y_i = y_plus_16_i - 16;
        const off_y: u16 = @intCast(mem.io.LY - y_i);
        const yflip = ppu.current_sprite_attrs.?.yflip;
        break :blk switch (yflip) {
            false => off_y,
            true => if (big) 15 - off_y else 7 - off_y,
        };
    };
    const off_x: u16 = blk: {
        const x_plus_8_i: i16 = sprite.x_plus_8;
        const x_i = x_plus_8_i - 8;
        break :blk @intCast(ppu.pixel_x - x_i);
    };

    const tile_index: u16 = if (big) sprite.tile_index & 0xFE else sprite.tile_index & 0xFF;
    const addr: u16 = 0x8000 + 16 * tile_index + 2 * off_y;
    ppu.sprite_tile_low = mem.readByte(addr);
    ppu.sprite_tile_high = mem.readByte(addr + 1);
    ppu.sprite_tile_idx = @intCast(off_x);
}

fn getPixelColorID(low: u8, high: u8, index: u3, flip: bool) u2 {
    const real_idx = if (flip) index else 7 - index;
    const mask = @as(u8, 0x01) << real_idx;
    const l: u1 = @intFromBool(low & mask == mask);
    const h: u2 = @intFromBool(high & mask == mask);
    return h << 1 | l;
}

fn selectPixel(ppu: Ppu, mem: *const Memory, bg_color_id: u2, sprite_color_id: u2) u2 {
    // NOTE: only called if there is a sprite being rendered
    const attrs = ppu.current_sprite_attrs.?;
    const bg_color = mem.io.BGP.get(bg_color_id);
    // if the sprite pixel is transparent
    if (sprite_color_id == 0) return bg_color;
    if (mem.io.LCDC.obj_enable) {
        const sprite_color = switch (attrs.palette) {
            0 => mem.io.OBP0.get(sprite_color_id),
            1 => mem.io.OBP1.get(sprite_color_id),
        };

        switch (attrs.priority) {
            0 => return sprite_color,
            1 => {
                return if (bg_color_id == 0) sprite_color else bg_color;
            },
        }
    } else return bg_color;
}
fn nextPixel(ppu: *Ppu, mem: *const Memory) u8 {

    if (ppu.next_sprite) |s| {
        if (ppu.pixel_x + 8 >= s.x_plus_8 and ppu.pixel_x < s.x_plus_8 and ppu.current_sprite_attrs == null) {
            ppu.current_sprite_attrs = s.attrs;
            getSpriteTile(ppu, mem);
            ppu.next_sprite = ppu.found_sprites.popOrNull();
        }
    }

    const color = blk: {
        const bg_color_id = switch (mem.io.LCDC.bg_window_enable) {
            true => getPixelColorID(ppu.bg_tile_low, ppu.bg_tile_high, ppu.bg_tile_idx, false),
            false => 0,
        };
        if (ppu.current_sprite_attrs) |attrs| {
            const sprite_color_id = getPixelColorID(
                ppu.sprite_tile_low,
                ppu.sprite_tile_high,
                ppu.sprite_tile_idx,
                attrs.xflip,
            );
            break :blk ppu.selectPixel(mem, bg_color_id, sprite_color_id);
        } else break :blk mem.io.BGP.get(bg_color_id);
    };

    ppu.pixel_x += 1;

    // just rendered last pixel
    if (ppu.bg_tile_idx == 7) {
        ppu.getBgTile(mem);
    } else {
        ppu.bg_tile_idx += 1;
    }
    if (ppu.current_sprite_attrs != null) {
        if (ppu.sprite_tile_idx == 7) {
            ppu.current_sprite_attrs = null;
        } else {
            ppu.sprite_tile_idx += 1;
        }
    }
    return colors[color];
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
    if (a.x_plus_8 == b.x_plus_8) {
        return a.oam_index > b.oam_index;
    }
    return a.x_plus_8 > b.x_plus_8;
}
fn sortFoundSprites(ppu: *Ppu) void {
    std.mem.sort(FoundSprite, ppu.found_sprites.slice(), {}, cmpFoundSpriteLT);
}
