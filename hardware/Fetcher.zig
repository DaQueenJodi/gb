const std = @import("std");
const assert = std.debug.assert;
const Fifo = std.fifo.LinearFifo;
const FoundSprite = @import("Ppu.zig").FoundSprite;

const Ppu = @import("Ppu.zig");
const Memory = @import("Memory.zig");

pub const OtherPixelProperties = struct {
    color: u2,
};
pub const SpritePixelProperties = struct {
    color: u2,
    palette: u1,
    priority_bit: u1,
};

const FetcherState = enum { get_tile, get_tile_data_low, get_tile_data_high, push };

const SpriteFifo = Fifo(SpritePixelProperties, .{ .Static = 16 });
const OtherFifo = Fifo(OtherPixelProperties, .{ .Static = 8 });

const Fetcher = @This();

first_tile: bool = true,
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
    fetcher.state = .get_tile;
    fetcher.fetcher_x = 0;
    fetcher.sprite_fifo.discard(fetcher.sprite_fifo.count);
    fetcher.other_fifo.discard(fetcher.other_fifo.count);
    fetcher.hit_sprite_oam = null;
    fetcher.working_on_sprite = false;
}
pub fn tick(fetcher: *Fetcher, ppu: Ppu, mem: *Memory) !void {
    if (!fetcher.rendering_window and ppu.wy_condition and mem.io.LCDC.window_enable) {
        if (ppu.x + 7 == mem.io.WX and mem.io.WX >= 7 and mem.io.WX < 166 + 7) {
            fetcher.rendering_window = true;
            fetcher.state = .get_tile;
            fetcher.other_fifo.discard(fetcher.other_fifo.count);
        }
    }

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
                    fetcher.other_data_backup_data = .{
                        .l = fetcher.tile_data_low,
                        .h = fetcher.tile_data_high,
                    };
                    std.log.err("STARTED WORKING ON SPRITE: {},{}", .{ppu.x, mem.io.LY});
                    const addr = getSpriteTileAddress(sprite, mem);
                    fetcher.tile_data_low = mem.readByte(addr);
                    fetcher.tile_data_high = mem.readByte(addr + 1);
                    if (try fetcher.push()) {
                        fetcher.state = .get_tile;
                        fetcher.fetcher_x +%= 1;
                    }
                }
            },
            .push => {
                if (try fetcher.push()) {
                    fetcher.state = .get_tile;
                    fetcher.fetcher_x +%= 1;
                }
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
        const x = fetcher.fetcher_x - @divFloor(mem.io.WX - 7, 8);
        const y: u16 = @divFloor(fetcher.window_line_counter, 8);
        const off = y *% 32 +% x;
        fetcher.tile_number = mem.readByte(tilemap_addr + off);
    } else {
        const x: u16 = (@divFloor(mem.io.SCX, 8) + fetcher.fetcher_x) & 0x1F;
        assert(x < 32);
        const y: u16 = @divFloor((ly + mem.io.SCY) & 0xFF, 8);
        const off = y * 32 + x;
        fetcher.tile_number = mem.readByte(tilemap_addr + off);
    }
}
fn getTileDataLow(fetcher: *Fetcher, mem: *Memory) void {
    const ly: u16 = mem.io.LY;
    const signed = mem.io.LCDC.bg_window_tile_data_area == 0;

    const tile_number: u16 = fetcher.tile_number;
    const tile_addr = if (signed and tile_number < 128) blk: {
        break :blk 0x9000 + tile_number * 16;
    } else blk: {
        break :blk 0x8000 + tile_number * 16;
    };

    const offset: u16 = switch (fetcher.rendering_window) {
        true => 2 * @mod(fetcher.window_line_counter, 8),
        false => 2 * @mod(ly + mem.io.SCY, 8),
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

    if (fetcher.first_tile) {
        fetcher.first_tile = false;
        fetcher.state = .get_tile;
    }
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
        for (0..8) |n| {
            const sprite = fetcher.hit_sprite_oam.?;
            const flipped_n = if (sprite.attributes.xflip) n else 7 - n;
            const l: u1 = @intFromBool(low_bits.isSet(flipped_n));
            const h: u2 = @intFromBool(high_bits.isSet(flipped_n));
            fetcher.sprite_fifo.writeItem(.{
                .color = (h << 1) | l,
                .priority_bit = sprite.attributes.priority,
                .palette = sprite.attributes.palette,
            }) catch unreachable;
        }
        fetcher.working_on_sprite = false;
        fetcher.hit_sprite_oam = null;
        if (fetcher.other_data_backup_data) |backup| {
            fetcher.tile_data_low = backup.l;
            fetcher.tile_data_high = backup.h;
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
            return true;
        } else return false;
    }
}


fn getSpriteTileAddress(s: FoundSprite, mem: *Memory) u16 {
    const big = mem.io.LCDC.obj_size == 1;
    const tile_idx: u16 = if (big) s.tile_idx & 0xFE else s.tile_idx;
    const ly_i: i16 = mem.io.LY;
    const y_plus_16_i: i16 = s.y_plus_16;
    const y_off: u8 = @intCast(ly_i - (y_plus_16_i - 16));
    const masked_y_off = if (big) y_off & 0b11111 else y_off & 0b1111;
    const flipped_y_off = blk: {
        if (s.attributes.yflip) {
            break :blk if (big) 16 - masked_y_off else 8 - masked_y_off; 
        } else break :blk masked_y_off;
    };
    //assert(big or flipped_y_off <= 8);
    return 0x8000 + tile_idx*16 + 2*flipped_y_off;
}
