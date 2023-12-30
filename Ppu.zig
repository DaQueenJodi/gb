const std = @import("std");
const assert = std.debug.assert;

const Memory = @import("Memory.zig");
const Ppu = @This();

const TileFlavor = enum { bg, window };

curr_tile_line: [2]u8 = undefined,
curr_tile_x: usize = 0,
curr_tile_index_in_map: usize = 0,
is_window: bool = false,
wy_condition: bool = false,
render_x: usize = 0,
render_y: usize = 0,
penalties: usize = 0,
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

pub fn tick(ppu: *Ppu, mem: *Memory) void {
    if (!mem.io.LCDC.lcd_ppu_enable) return;

    const scanline_dots = @mod(ppu.dots_count, DOTS_PER_SCANLINE+1);

    switch (ppu.mode) {
        .oam_scan => {
            if (mem.io.LY == mem.io.WX) {
                ppu.wy_condition = true;
            }
            if (scanline_dots == OAM_END) {
                ppu.mode = .drawing;
                ppu.render_x = 0;
                // set up for bg drawing
                // see how much SCX and SCY cuts off of the first sprite
                const line_of_tile = @mod(mem.io.SCY, 8);
                const tile_addr_off = (mem.io.SCY +% line_of_tile) *% 32 +% (mem.io.SCX +% ppu.render_x);
                ppu.curr_tile_x = @mod(mem.io.SCX, 8);
                ppu.curr_tile_line = loadBgTileLine(mem, @intCast(tile_addr_off), line_of_tile);
            }
        },
        .drawing => {
            if (ppu.wy_condition and
                mem.io.LCDC.window_enable and
                mem.io.LCDC.bg_window_enable and
                ppu.render_x + 7 == mem.io.WX)
            {
                // set up for window drawing
                //std.debug.print("drawing window!\n", .{});
                ppu.is_window = true;
                ppu.curr_tile_x = 0;
                ppu.curr_tile_line = loadWindowTileLine(mem, 0, 0);
            }
            ppu.drawPixel(mem);
            ppu.render_x += 1;
            ppu.curr_tile_x += 1;
            if (ppu.curr_tile_x == 8) {
                ppu.curr_tile_x = 0;
                ppu.curr_tile_line = switch (ppu.is_window) {
                    true => loadWindowTileLine(mem, @intCast(ppu.curr_tile_index_in_map + 1), @mod(ppu.render_y - mem.io.WY, 8)),
                    false => loadBgTileLine(mem, @intCast(ppu.curr_tile_index_in_map + 1), @mod(ppu.render_y + mem.io.SCY, 8)),
                };
            }
            if (scanline_dots == DRAWING_END_BASE + ppu.penalties) {
                ppu.mode = .hblank;
            }
        },
        .hblank => {
            if (scanline_dots == DOTS_PER_SCANLINE) {
                ppu.render_y += 1;
                mem.io.LY += 1;
                if (mem.io.LY == 145) {
                    ppu.mode = .vblank;
                    ppu.is_window = false;
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
    ppu.render_x = 0;
    ppu.render_y = 0;
    ppu.wy_condition = false;
    ppu.is_window = false;
    ppu.dots_count = 0;
    ppu.penalties = 0;
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
            0 => .transparent,
            1 => .light_grey,
            2 => .dark_grey,
            3 => .black
        };
        FB[ppu.render_y * SCREEN_WIDTH + ppu.render_x] = real_color;
    }
}
