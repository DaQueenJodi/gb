const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Fifo = std.fifo.LinearFifo;

const Memory = @import("Memory.zig");
const Ppu = @This();

const TileFlavor = enum { bg, window };


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

    const scanline_dots = @mod(ppu.dots_count, DOTS_PER_SCANLINE+1);
    switch (ppu.mode) {
        .oam_scan => {
            if (mem.io.LY == mem.io.WY) {
                ppu.wy_condition = true;
            }
            if (scanline_dots == OAM_END) {
                ppu.mode = .drawing;
            }
        },
        .drawing => {
            try ppu.fetcher.tick(ppu.*, mem);
            if (ppu.fetcher.other_fifo.readItem()) |p| {
                const color = mem.io.BGP.get(p.color);
                const col: Color = switch (color) {
                    0 => .white,
                    1 => .light_grey,
                    2 => .dark_grey,
                    3 => .black
                };
                //std.debug.print("pixel rendered: {}\n", .{p});
                FB[mem.io.LY*SCREEN_WIDTH+ppu.x] = col;
                ppu.x +%= 1;
            }
            if (scanline_dots == DRAWING_END_BASE) {
                ppu.mode = .hblank;
            }
        },
        .hblank => {
            if (scanline_dots == DOTS_PER_SCANLINE) {
                ppu.fetcher.fetcher_x = 0;
                ppu.x = 0;
                mem.io.LY +%= 1;
                if (mem.io.LY == 145) {
                    ppu.mode = .vblank;
                    ppu.wy_condition = false;
                }
            }
        },
        .vblank => {
            // itll be 0 because scanline_dots is modulused around HBLANK_END
            if (scanline_dots == DOTS_PER_SCANLINE and ppu.dots_count != DOTS_PER_FRAME) {
                mem.io.LY += 1;
            }
        },
    }

    if (ppu.dots_count == DOTS_PER_FRAME) return;
    ppu.dots_count += 1;
}

pub fn resetFrame(ppu: *Ppu, mem: *Memory) void {
    mem.io.LY = 0;
    ppu.wy_condition = false;
    ppu.dots_count = 0;
    ppu.mode = .oam_scan;
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
fn drawPixel(ppu: Ppu, mem: *Memory) void {
    const lbyte = ppu.curr_tile_line[0];
    const rbyte = ppu.curr_tile_line[1];
    const mask = @as(u8, 0x1) << @intCast(ppu.curr_tile_x);
    const l: u1 = @intFromBool(lbyte & mask > 0);
    const r: u2 = @intFromBool(rbyte & mask > 0);
    const color_id = r << 1 | l;
    const color = mem.io.BGP.get(color_id);

    if (ppu.is_window) {
        const real_color: Color = switch (color) {
            0 => .white,
            1 => .light_grey,
            2 => .dark_grey,
            3 => .black
        };
        FB[ppu.render_y * SCREEN_WIDTH + ppu.render_x] = real_color;
    } else {
        const real_color: Color = switch (color) {
            0 => .white,
            1 => .light_grey,
            2 => .dark_grey,
            3 => .black
        };
        FB[ppu.render_y * SCREEN_WIDTH + ppu.render_x] = real_color;
    }
}



const OtherPixelProperties = struct {
    color: u2,
    priority_bit: u1,
};
const SpritePixelProperties = struct {
    color: u2,
    pallete: u3,
    priority_bit: u1,
};

const FetcherState = enum {
    get_tile,
    get_tile_data_low,
    get_tile_data_high,
    sleep,
    push
};

const SpriteFifo = Fifo(SpritePixelProperties, .{.Static = 16 });
const OtherFifo = Fifo(OtherPixelProperties, .{.Static = 16 });

const Fetcher = struct {
    fetcher_x: u8 = 0,
    window_line_counter: u8 = 0,
    tile_number: u8 = 0,
    tile_data_low: u8 = undefined,
    tile_data_high: u8 = undefined,
    rendering_window: bool = true,
    should_waiting: bool = false,
    state: FetcherState = .get_tile,
    sprite_fifo: SpriteFifo = SpriteFifo.init(),
    other_fifo: OtherFifo = OtherFifo.init(),
    pub fn reset(fetcher: *Fetcher) void {
        fetcher.sprite_fifo.discard(fetcher.sprite_fifo.readableLength());
        fetcher.other_fifo.discard(fetcher.other_fifo.readableLength());
    }
    pub fn tick(fetcher: *Fetcher, ppu: Ppu, mem: *Memory) !void {
        switch (fetcher.state) {
            .get_tile => {
                fetcher.getTile(ppu, mem);
                fetcher.state = .get_tile_data_low;
            },
            .get_tile_data_low => {
                fetcher.getTileDataLow(mem);
                fetcher.state = .get_tile_data_high;
            },
            .get_tile_data_high => {
                fetcher.getTileDataLow(mem);
                fetcher.state = .sleep;
            },
            .sleep => {
                fetcher.state = .push;
            },
            .push => {
                try fetcher.push();
            },
        }
        fetcher.should_waiting = !fetcher.should_waiting and fetcher.state != .push;
    }
    fn getTile(fetcher: *Fetcher, ppu: Ppu, mem: *Memory) void {
        const tilemap_addr: u16 = blk: {
            if (mem.io.LCDC.bg_tile_map_area == 1 and !ppu.wy_condition) {
                break :blk 0x9C00;
            }
            if (mem.io.LCDC.window_tile_map_area == 1 and ppu.wy_condition) {
                break :blk 0x9C00;
            }
            break :blk 0x9800;
        };
        if (fetcher.rendering_window) {
            const y: u8 = @mod(fetcher.window_line_counter, 8);
            const off= y *% 32 +% fetcher.fetcher_x;
            fetcher.tile_number = mem.readByte(tilemap_addr + off);
        } else {
            const scx = mem.io.SCX;

            const x = (@divFloor(scx, 8) + fetcher.fetcher_x) & 0x1F;
            assert(x < 32);
            const y = (mem.io.LY +% scx) & 255;
            const off = y *% 32 +% x;
            fetcher.tile_number = mem.readByte(tilemap_addr + off);
        }
    }
    fn getTileDataLow(fetcher: *Fetcher, mem: *Memory) void {
        const signed, const tilemap: u16 = switch (mem.io.LCDC.bg_window_tile_data_area) {
            0 => .{true, 0x9000},
            1 => .{false, 0x8000}
        };
        const tile_addr: u16 = switch (signed) {
            false => blk: {
                break :blk tilemap + fetcher.tile_number *% 16;
            },
            true => blk: {
                const ni: u8 = @bitCast(fetcher.tile_number);
                break :blk tilemap + ni *% 16;
            }
        };
        const offset: u16 = switch (fetcher.rendering_window) {
            true => 2 * @mod(fetcher.window_line_counter, 8),
            false => 2 * @mod(mem.io.LY +% mem.io.SCY, 8)
        };

        fetcher.tile_data_low = mem.readByte(tile_addr + offset);
    }
    fn getTileDataHigh(fetcher: *Fetcher, mem: *Memory) void {
        const signed, const tilemap: u16 = switch (mem.io.LCDC.bg_window_tile_data_area) {
            0 => .{true, 0x9000},
            1 => .{false, 0x8000}
        };
        const tile_addr: u16 = switch (signed) {
            false => blk: {
                break :blk tilemap + fetcher.tile_number *% 16;
            },
            true => blk: {
                const ni: u8 = @bitCast(fetcher.tile_number);
                break :blk tilemap + ni *% 16;
            }
        };
        const offset: u16 = switch (fetcher.rendering_window) {
            true => 2 * @mod(fetcher.window_line_counter, 8),
            false => 2 * @mod(mem.io.LY +% mem.io.SCY, 8)
        };

        fetcher.tile_data_low = mem.readByte(tile_addr + offset +% 1);
    }
    fn push(fetcher: *Fetcher) !void {
        if (fetcher.other_fifo.count == 0) {
            const low_bits = std.bit_set.IntegerBitSet(8){.mask = fetcher.tile_data_low};
            const high_bits = std.bit_set.IntegerBitSet(8){.mask = fetcher.tile_data_high};
            for (0..8) |n| {
                const bn = 7 - n;
                const l: u1 = @intFromBool(low_bits.isSet(bn));
                const h: u2 = @intFromBool(high_bits.isSet(bn));
                try fetcher.other_fifo.writeItem(.{.color = (h << 1) | l, .priority_bit = 0});
            }
        }
        fetcher.fetcher_x +%= 1;
    }
};


