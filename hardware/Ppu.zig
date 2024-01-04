const std = @import("std");
const assert = std.debug.assert;

const Fetcher = @import("Fetcher.zig");
const Memory = @import("Memory.zig");
const Ppu = @This();
const SpritePixelProperties = Fetcher.SpritePixelProperties;
const OtherPixelProperties = Fetcher.OtherPixelProperties;

const TileFlavor = enum { bg, window };

const SpriteAttributes = packed struct {
    _cgb_stuff_i_dont_care_about: u4,
    palette: u1,
    xflip: bool,
    yflip: bool,
    priority: u1,
};

pub const FoundSprite = struct {
    x_plus_8: u8,
    y_plus_16: u8,
    tile_idx: u8,
    attributes: SpriteAttributes,
};
old_stat_line: bool = false,
found_sprites: std.BoundedArray(FoundSprite, 10) = .{},
oam_index: u8 = 0,
just_finished: bool = false,
fetcher: Fetcher = .{},
wy_condition: bool = false,
x: usize = 0,
dots_count: usize = 0,

const SCREEN_WIDTH = 160;
const SCREEN_HEIGHT = 144;
const DOTS_PER_SCANLINE = 456;
const DOTS_PER_FRAME = 70224;

const OAM_END = 80;
const DRAWING_END_BASE = 252;
const HBLANK_END = 456;

const Color = enum {
    transparent,
    white,
    light_grey,
    dark_grey,
    black,
};
pub fn handleLCDInterrupts(ppu: *Ppu, mem: *Memory) void {
    const stat = mem.io.STAT;
    // TODO: do this bitwise
    const stat_line =
        (stat.mode_0_select and stat.ppu_mode == .hblank) or
        (stat.mode_1_select and stat.ppu_mode == .vblank) or
        (stat.mode_2_select and stat.ppu_mode == .oam_scan) or
        (stat.lyc_select and stat.lyc_eq_ly);

    if (stat_line and !ppu.old_stat_line) {
       mem.io.IF.stat = true;
    }
    ppu.old_stat_line = stat_line;
}

pub var FB = std.mem.zeroes([SCREEN_WIDTH * SCREEN_HEIGHT]Color);
pub fn tick(ppu: *Ppu, mem: *Memory) !void {
    if (!mem.io.LCDC.lcd_ppu_enable) return;

    if (mem.io.LY == mem.io.LYC) {
        if (!mem.io.STAT.lyc_eq_ly) mem.io.STAT.lyc_eq_ly = true;
    } else mem.io.STAT.lyc_eq_ly = false;
    switch (mem.io.STAT.ppu_mode) {
        .oam_scan => {
            if (!ppu.wy_condition and mem.io.LY == mem.io.WY) {
                ppu.wy_condition = true;
            }

            // check an object every two dots
            if (ppu.oam_index < 40 and @mod(ppu.dots_count, 2) == 0 and ppu.found_sprites.len < 10) {
                const idx: u16 = ppu.oam_index;
                const addr = 0xFE00 + idx * 4;
                assert(addr <= 0xFE9F);

                const y = mem.readByte(addr);
                const max_off: u8 = if (mem.io.LCDC.obj_size == 1) 16 else 8;
                if (mem.io.LY + 16 >= y and mem.io.LY + 16 - max_off <= y) {
                    const x = mem.readByte(addr + 1);
                    const tile_index = mem.readByte(addr + 2);
                    const attrs = mem.readByte(addr + 3);
                    ppu.found_sprites.append(.{
                        .x_plus_8 = x,
                        .y_plus_16 = y,
                        .tile_idx = tile_index,
                        .attributes = @bitCast(attrs),
                    }) catch unreachable;
                    std.log.err("FOUND SPRITE AT: {},{}", .{x - 8, y - 16});
                }

                ppu.oam_index += 1;
            }
            if (ppu.dots_count == OAM_END) {
                mem.io.STAT.ppu_mode = .drawing;
                ppu.fetcher.reset();
            }
        },
        .drawing => {
            try ppu.fetcher.tick(ppu.*, mem);
            if (ppu.fetcher.hit_sprite_oam != null) return;
            const bg = ppu.fetcher.other_fifo.readItem();
            const color = blk: {
                if (bg == null) break :blk null;
                const sprite = ppu.fetcher.sprite_fifo.readItem();
                if (!mem.io.LCDC.bg_window_enable) {
                    break :blk getColorFromShadeID(mem.io.BGP.get(0));
                }
                const bg_pixel_color = getColorFromBgPixel(bg.?, mem);
                if (!mem.io.LCDC.obj_enable) break :blk bg_pixel_color;
                if (sprite) |s| {
                    const sprite_pixel_color = getColorFromSpritePixel(s, mem);
                    if (sprite_pixel_color == .transparent) break :blk bg_pixel_color;
                    if (s.priority_bit == 0) {
                        std.log.err("SPRITE PIXEL AT: {},{}", .{ppu.x, mem.io.LY});
                        break :blk sprite_pixel_color;
                    } else {
                        break :blk if (bg_pixel_color == .white) sprite_pixel_color else bg_pixel_color;
                    }
                } else break :blk bg_pixel_color;
            };

            if (color) |col| {
                const ly: u16 = @intCast(mem.io.LY);
                {
                    @setRuntimeSafety(false);
                    FB[ly * SCREEN_WIDTH + ppu.x] = col;
                }
                ppu.x += 1;
            }

            if (ppu.x == 160) {
                mem.io.STAT.ppu_mode = .hblank;
            }
        },
        .hblank => {
            if (ppu.dots_count == DOTS_PER_SCANLINE) {
                if (mem.io.LY == 143) {
                    mem.io.STAT.ppu_mode = .vblank;
                    mem.io.IF.vblank = true;
                } else {
                    mem.io.STAT.ppu_mode = .oam_scan;
                    ppu.found_sprites.len = 0;
                    ppu.oam_index = 0;
                }
                if (ppu.fetcher.rendering_window) {
                    ppu.fetcher.window_line_counter += 1;
                    ppu.fetcher.rendering_window = false;
                }
                ppu.fetcher.first_tile = true;
                mem.io.LY += 1;
                ppu.dots_count = 0;
                ppu.x = 0;
            }
        },
        .vblank => {
            if (mem.io.LY == 153 and ppu.dots_count == DOTS_PER_SCANLINE) {
                ppu.just_finished = true;

                mem.io.STAT.ppu_mode = .oam_scan;
                ppu.oam_index = 0;
                ppu.found_sprites.len = 0;

                mem.io.LY = 0;
                ppu.dots_count = 0;


                ppu.wy_condition = false;
            }

            if (ppu.dots_count == DOTS_PER_SCANLINE) {
                mem.io.LY +%= 1;
                ppu.dots_count = 0;
            }
        },
    }

    if (ppu.dots_count == DOTS_PER_FRAME) return;
    ppu.dots_count += 1;
}


fn getColorFromShadeID(shade_id: u2) Color {
    return switch (shade_id) {
        0 => .white,
        1 => .light_grey,
        2 => .dark_grey,
        3 => .black,
    };
}

fn getColorFromSpritePixel(pixel: SpritePixelProperties, mem: *Memory) Color {
    if (pixel.color == 0) return .transparent;
    const shade_id = switch (pixel.palette) {
        0 => mem.io.OBP0.get(pixel.color),
        1 => mem.io.OBP1.get(pixel.color),
    };
    return getColorFromShadeID(shade_id);
}

fn getColorFromBgPixel(pixel: OtherPixelProperties, mem: *Memory) Color {
    const shade_id = mem.io.BGP.get(pixel.color);
    return getColorFromShadeID(shade_id);
}
