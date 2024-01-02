const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Fifo = std.fifo.LinearFifo;

const Memory = @import("Memory.zig");
const Ppu = @This();

const TileFlavor = enum { bg, window };


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
    tile_idx: u8,
    attributes: SpriteAttributes,
};
found_sprites: std.BoundedArray(FoundSprite, 10) = .{},
oam_index: u8 = 0,
just_finished: bool = false,
fetcher: Fetcher = .{},
wy_condition: bool = false,
x: usize = 0,
mode: Mode = .oam_scan,
dots_count: usize = 0,

const SCREEN_WIDTH = 160;
const SCREEN_HEIGHT = 144;
const DOTS_PER_SCANLINE = 456;
const DOTS_PER_FRAME = 70224;

const OAM_END = 80;
const DRAWING_END_BASE = 252;
const HBLANK_END = 456;

const Mode = enum {
    hblank,
    drawing,
    oam_scan,
    vblank,
};

const Color = enum {
    transparent,
    white,
    light_grey,
    dark_grey,
    black,
};

pub fn tick(ppu: *Ppu, mem: *Memory) !void {
    if (!mem.io.LCDC.lcd_ppu_enable) return;

    if (mem.io.LY == mem.io.LYC) {
        if (!mem.io.STAT.lyc_eq_ly) {
            mem.io.STAT.lyc_eq_ly = true;
            if (mem.io.STAT.lyc_select) mem.io.IF.stat = true;
        }
    } else mem.io.STAT.lyc_eq_ly = false;
    switch (ppu.mode) {
        .oam_scan => {
            if (mem.io.LY == mem.io.WY) {
                ppu.wy_condition = true;
            }
            // check an object every two dots
            if (ppu.oam_index < 40 and @mod(ppu.dots_count, 2) == 0 and ppu.found_sprites.len < 10) {
                const idx: u16 = ppu.oam_index;
                const addr = 0xFE00 + idx * 4;
                assert(addr <= 0xFE9F);

                const y = mem.readByte(addr);
                if (mem.io.LY + 16 >= y and mem.io.LY + 8 <= y) {
                    const x = mem.readByte(addr + 1);
                    const tile_index = mem.readByte(addr + 2);
                    const attrs = mem.readByte(addr + 3);
                    ppu.found_sprites.append(.{
                        .x_plus_8 = x,
                        .y_plus_16 = y,
                        .tile_idx = tile_index,
                        .attributes = @bitCast(attrs),
                    }) catch unreachable;
                }

                ppu.oam_index += 1;
            }
            if (ppu.dots_count == OAM_END) {
                ppu.mode = .drawing;
                ppu.fetcher.reset();
            }
        },
        .drawing => {
            try ppu.fetcher.tick(ppu.*, mem);
            const bg = ppu.fetcher.other_fifo.readItem();
            const sprite = ppu.fetcher.sprite_fifo.readItem();
            // TODO priority
            const color = blk: {
                if (bg == null) break :blk null;
                const bg_pixel_color = getColorFromBgPixel(bg.?, mem);
                if (sprite) |s| {
                    const sprite_pixel_color = getColorFromSpritePixel(s, mem);
                    if (sprite_pixel_color == .transparent) break :blk bg_pixel_color;
                    if (s.priority_bit == 0) {
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
                ppu.x +%= 1;
            }

            if (ppu.x == 160) {
                ppu.mode = .hblank;
                ppu.x = 0;
            }
        },
        .hblank => {
            if (ppu.dots_count == DOTS_PER_SCANLINE) {
                if (mem.io.LY == 143) {
                    ppu.mode = .vblank;
                    mem.io.IF.vblank = true;
                } else {
                    ppu.mode = .oam_scan;
                    ppu.found_sprites.len = 0;
                    ppu.oam_index = 0;
                }
                mem.io.LY +%= 1;
                ppu.dots_count = 0;
                ppu.x = 0;
                ppu.fetcher.fetcher_x = 0;
            }
        },
        .vblank => {
            if (mem.io.LY == 153 and ppu.dots_count == DOTS_PER_SCANLINE) {
                ppu.just_finished = true;

                ppu.mode = .oam_scan;
                ppu.oam_index = 0;
                ppu.found_sprites.len = 0;

                mem.io.LY = 0;
                ppu.fetcher.window_line_counter = 0;
                ppu.dots_count = 0;
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

fn loadWindowTileLine(mem: *Memory, addr_off: u16, line: usize) [2]u8 {
    assert(line <= 8);
    const wmap: u16 = switch (mem.io.LCDC.window_tile_map_area) {
        0 => 0x9800,
        1 => 0x9C00,
    };
    const idx = mem.readByte(wmap + addr_off);
    const addr = mem.getTileMapAddr(idx) + 2 * line;
    std.log.info("WIN: {X:0>2}", .{idx});
    return .{ mem.readByte(addr), mem.readByte(addr + 1) };
}
fn loadBgTileLine(mem: *Memory, addr_off: u16, line: usize) [2]u8 {
    assert(line <= 8);
    const bmap: u16 = switch (mem.io.LCDC.bg_tile_map_area) {
        0 => 0x9800,
        1 => 0x9C00,
    };
    const idx = mem.readByte(bmap + addr_off);
    std.log.info("BG: {X:0>2}", .{idx});
    const addr = mem.getTileMapAddr(idx) + 2 * line;
    return .{ mem.readByte(addr), mem.readByte(addr + 1) };
}

pub var FB = std.mem.zeroes([SCREEN_WIDTH * SCREEN_HEIGHT]Color);

const OtherPixelProperties = struct {
    color: u2,
};
const SpritePixelProperties = struct {
    color: u2,
    palette: u1,
    priority_bit: u1,
};

const FetcherState = enum { get_tile, get_tile_data_low, get_tile_data_high, push };

const SpriteFifo = Fifo(SpritePixelProperties, .{ .Static = 8 });
const OtherFifo = Fifo(OtherPixelProperties, .{ .Static = 8 });

const Fetcher = struct {
    working_on_sprite: bool = false,
    hit_sprite_oam: ?FoundSprite = null,
    fetcher_x: u8 = 0,
    window_line_counter: u8 = 0,
    tile_number: u8 = 0,
    tile_data_low: u8 = undefined,
    tile_data_high: u8 = undefined,
    rendering_window: bool = false,
    should_waiting: bool = false,
    state: FetcherState = .get_tile,
    sprite_fifo: SpriteFifo = SpriteFifo.init(),
    other_data_backup_data: ?struct { l: u8, h: u8 } = null,
    other_fifo: OtherFifo = OtherFifo.init(),
    pub fn reset(fetcher: *Fetcher) void {
        fetcher.sprite_fifo.discard(fetcher.sprite_fifo.count);
        fetcher.other_fifo.discard(fetcher.other_fifo.count);
        fetcher.hit_sprite_oam = null;
        fetcher.working_on_sprite = false;
    }
    pub fn tick(fetcher: *Fetcher, ppu: Ppu, mem: *Memory) !void {

        if (fetcher.hit_sprite_oam == null) {
            fetcher.hit_sprite_oam = blk: {
                for (ppu.found_sprites.slice()) |s| {
                    if (ppu.x + 8 == s.x_plus_8) {
                        break :blk s;
                    }
                }
                break :blk null;
            };
        }
        if (!fetcher.should_waiting) {
            switch (fetcher.state) {
                .get_tile => {
                    fetcher.getTile(mem);
                    fetcher.state = .get_tile_data_low;
                },
                .get_tile_data_low => {
                    fetcher.getTileDataLow(mem);
                    fetcher.state = .get_tile_data_high;
                },
                .get_tile_data_high => {
                    fetcher.getTileDataHigh(mem);
                    fetcher.state = .push;

                    if (fetcher.hit_sprite_oam) |sprite| {
                        fetcher.working_on_sprite = true;

                        // if the bg fifo isn't empty, save the fetched pixels
                        if (fetcher.other_fifo.count > 0) {
                            fetcher.other_data_backup_data = .{
                                .l = fetcher.tile_data_low,
                                .h = fetcher.tile_data_high,
                            };
                        }
                        const tile_idx16: u16 = sprite.tile_idx;
                        const tile_addr: u16 = 0x8000 + tile_idx16  * 16;
                        assert(tile_addr <= 0x8FFF);
                        const y_plus_16_i: i16 = @intCast(sprite.y_plus_16);
                        const ly_i: i16 = @intCast(mem.io.LY);
                        const tile_y: u8 = @intCast(@mod(y_plus_16_i - 16 + ly_i, 8));
                        const flipped_tile_y = if (sprite.attributes.yflip) 7 - tile_y else tile_y;
                        assert(tile_y <= 7);

                        //if (sprite.attributes.yflip) std.log.err("yflip", .{});

                        const y_off: u16 = 2 * flipped_tile_y;
                        fetcher.tile_data_low = mem.readByte(tile_addr + y_off);
                        fetcher.tile_data_high = mem.readByte(tile_addr + y_off + 1);

                        std.log.err("low: {}", .{fetcher.tile_data_low});
                        std.log.err("high: {}", .{fetcher.tile_data_high});
                    }
                },
                .push => {
                    if (try fetcher.push()) fetcher.state = .get_tile;
                },
            }
        } else fetcher.should_waiting = !fetcher.should_waiting and fetcher.state != .push;
    }
    fn getTile(fetcher: *Fetcher, mem: *Memory) void {
        const ly: u16 = mem.io.LY;
        const tilemap_addr: u16 = blk: {
            if (fetcher.rendering_window) {
                break :blk switch (mem.io.LCDC.window_tile_map_area) {
                    0 => 0x9800,
                    1 => 0x9C00,
                };
            } else {
                break :blk switch (mem.io.LCDC.bg_tile_map_area) {
                    0 => 0x9800,
                    1 => 0x9C00,
                };
            }
        };
        if (fetcher.rendering_window) {
            const y: u16 = @mod(fetcher.window_line_counter, 8);
            const x = (fetcher.fetcher_x & 0x1F);
            const off = y *% 32 +% x;
            fetcher.tile_number = mem.readByte(tilemap_addr + off);
        } else {
            const x: u16 = (@divFloor(mem.io.SCX, 8) +% fetcher.fetcher_x) & 0x1F;
            assert(x < 32);
            const y: u16 = @divFloor((ly +% mem.io.SCY) & 255, 8);
            const off = y *% 32 +% x;
            fetcher.tile_number = mem.readByte(tilemap_addr + off);
        }
    }
    fn getTileDataLow(fetcher: *Fetcher, mem: *Memory) void {
        const ly: u16 = mem.io.LY;
        const signed = mem.io.LCDC.bg_window_tile_data_area == 0;

        const tile_number: u16 = fetcher.tile_number;
        const tile_addr = if (signed and tile_number < 128) blk: {
            break :blk 0x9000 + tile_number *% 16;
        } else blk: {
            break :blk 0x8000 + tile_number *% 16;
        };

        const offset: u16 = switch (fetcher.rendering_window) {
            true => 2 * @mod(fetcher.window_line_counter, 8),
            false => 2 * @mod(ly +% mem.io.SCY, 8),
        };
        fetcher.tile_data_low = mem.readByte(@intCast(tile_addr + offset));
    }
    fn getTileDataHigh(fetcher: *Fetcher, mem: *Memory) void {
        const ly: u16 = mem.io.LY;
        const signed = mem.io.LCDC.bg_window_tile_data_area == 0;

        const tile_number: u16 = fetcher.tile_number;
        const tile_addr = if (signed and tile_number < 128) blk: {
            break :blk 0x9000 + tile_number *% 16;
        } else blk: {
            break :blk 0x8000 + tile_number *% 16;
        };

        const offset: u16 = switch (fetcher.rendering_window) {
            true => 2 * @mod(fetcher.window_line_counter, 8),
            false => 2 * @mod(ly +% mem.io.SCY, 8),
        };

        fetcher.tile_data_high = mem.readByte(@intCast(tile_addr + offset + 1));
    }
    fn push(fetcher: *Fetcher) !bool {
        const low_bits = std.bit_set.IntegerBitSet(8){ .mask = fetcher.tile_data_low };
        const high_bits = std.bit_set.IntegerBitSet(8){ .mask = fetcher.tile_data_high };

        if (fetcher.working_on_sprite) {
            if (fetcher.sprite_fifo.count == 0) {
                for (0..8) |n| {
                    const sprite = fetcher.hit_sprite_oam.?;
                    const real_n = if (sprite.attributes.xflip) n else 7 - n;
                    const l: u1 = @intFromBool(low_bits.isSet(real_n));
                    const h: u2 = @intFromBool(high_bits.isSet(real_n));
                    try fetcher.sprite_fifo.writeItem(.{
                        .color = (h << 1) | l,
                        .priority_bit = sprite.attributes.priority,
                        .palette = sprite.attributes.palette,
                    });
                }
                fetcher.working_on_sprite = false;
                fetcher.hit_sprite_oam = null;
                if (fetcher.other_data_backup_data) |backup| {
                    fetcher.tile_data_low = backup.l;
                    fetcher.tile_data_high = backup.h;
                }
            }
            return false;
        } else {
            if (fetcher.other_fifo.count == 0) {
                for (0..8) |n| {
                    const bn = 7 - n;
                    const l: u1 = @intFromBool(low_bits.isSet(bn));
                    const h: u2 = @intFromBool(high_bits.isSet(bn));
                    try fetcher.other_fifo.writeItem(.{ .color = (h << 1) | l });
                }
                fetcher.fetcher_x +%= 1;
                return true;
            } else return false;
        }
    }
};

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
