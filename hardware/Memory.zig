const std = @import("std");
const Allocator = std.mem.Allocator;
const rl = @import("root").c;

const Memory = @This();

const KiB = 1024;

oam_transfer_data: ?struct {
    src_start: u16,
    cycle: u16 = 0,
},
sb_data: u8,
rom_mapped: bool,
bank0: [16 * KiB]u8,
bank1: [16 * KiB]u8,
vram: [8 * KiB]u8,
external_ram: [8 * KiB]u8,
wram0: [4 * KiB]u8,
wram1: [4 * KiB]u8,
oam: [0xA0]u8,
io: IoRegs,
hram: [0x7F]u8,
ie: IE,

const BOOT_ROM = @embedFile("bootroms/dmg_boot.bin");

pub fn create__(allocator: Allocator) !*Memory {
    const mem = try allocator.create(Memory);
    mem.oam_transfer_data = null;
    mem.rom_mapped = true;
    mem.io.LCDC.lcd_ppu_enable = false;
    mem.io.LY = 0;
    mem.io.SCX = 0;
    mem.io.SCY = 0;
    mem.io.IF = @bitCast(@as(u8, 0));
    mem.ie = @bitCast(@as(u8, 0));
    mem.io.STAT = @bitCast(@as(u8, 0));
    mem.io.STAT.ppu_mode = .oam_scan;
    return mem;
}

pub fn create(allocator: Allocator) !*Memory {
    const mem = try allocator.create(Memory);
    mem.oam_transfer_data = null;
    mem.rom_mapped = false;
    mem.io.LY = 0;

    mem.writeByte(0xFF05, 0x00);
    mem.writeByte(0xFF06, 0x00);
    mem.writeByte(0xFF07, 0x00);
    mem.writeByte(0xFF10, 0x80);
    mem.writeByte(0xFF11, 0xBF);
    mem.writeByte(0xFF12, 0xF3);
    mem.writeByte(0xFF14, 0xBF);
    mem.writeByte(0xFF16, 0x3F);
    mem.writeByte(0xFF17, 0x00);
    mem.writeByte(0xFF19, 0xBF);
    mem.writeByte(0xFF1A, 0x7F);
    mem.writeByte(0xFF1B, 0xFF);
    mem.writeByte(0xFF1C, 0x9F);
    mem.writeByte(0xFF1E, 0xBF);
    mem.writeByte(0xFF20, 0xFF);
    mem.writeByte(0xFF21, 0x00);
    mem.writeByte(0xFF22, 0x00);
    mem.writeByte(0xFF23, 0xBF);
    mem.writeByte(0xFF24, 0x77);
    mem.writeByte(0xFF25, 0xF3);
    mem.writeByte(0xFF26, 0xF1);
    mem.writeByte(0xFF40, 0x91);
    mem.writeByte(0xFF42, 0x00);
    mem.writeByte(0xFF43, 0x00);
    mem.writeByte(0xFF45, 0x00);
    mem.writeByte(0xFF47, 0xFC);
    mem.writeByte(0xFF48, 0xFF);
    mem.writeByte(0xFF49, 0xFF);
    mem.writeByte(0xFF4A, 0x00);
    mem.writeByte(0xFF4B, 0x00);
    mem.writeByte(0xFFFF, 0x00);

    return mem;
}

const BANK0_OFF = 0;
const BANK1_OFF = 0x4000;
const VRAM_OFF = 0x8000;
const EXTERNAL_RAM_OFF = 0xA000;
const WRAM0_OFF = 0xC000;
const WRAM1_OFF = 0xD000;
const OAM_OFF = 0xFE00;
const IO_OFF = 0xFF00;
const HRAM_OFF = 0xFF80;
const IE_OFF = 0xFFFF;

const ECHO_DIFF = 0xE000 - 0xC000;

pub const MemRange = enum { bank0, bank1, vram, wram0, wram1, echo, prohiboted, oam, io, hram, ie, external_ram };

fn rangeFromAddr(addr: usize) MemRange {
    return switch (addr) {
        BANK0_OFF...0x3FFF => .bank0,
        BANK1_OFF...0x7FFF => .bank1,
        VRAM_OFF...0x9FFF => .vram,
        EXTERNAL_RAM_OFF...0xBFFF => .external_ram,
        WRAM0_OFF...0xCFFF => .wram0,
        WRAM1_OFF...0xDFFF => .wram1,
        OAM_OFF...0xFE9F => .oam,
        IO_OFF...0xFF7F => .io,
        HRAM_OFF...0xFFFE => .hram,
        0xFFFF => .ie,
        0xE000...0xFDFF => .echo,
        0xFEA0...0xFEFF => .prohiboted,
        else => std.debug.panic("invalid range: {X:0<4}", .{addr}),
    };
}

pub fn readByte(self: Memory, addr: u16) u8 {
    const region = rangeFromAddr(addr);
    return switch (region) {
        .prohiboted => {
            std.log.warn("reading from prohiboted memory region: {X:0<4}", .{addr});
            return 0xFF;
        },
        .external_ram => self.external_ram[addr - EXTERNAL_RAM_OFF],
        .bank0 => {
            if (self.rom_mapped and addr - BANK0_OFF < 0x0100) {
                return BOOT_ROM[addr - BANK0_OFF];
            }
            return self.bank0[addr - BANK0_OFF];
        },
        .bank1 => self.bank1[addr - BANK1_OFF],
        .vram => self.vram[addr - VRAM_OFF],
        .oam => self.oam[addr - OAM_OFF],
        .io => self.ioReadByte(addr),
        .hram => self.hram[addr - HRAM_OFF],
        .wram0 => self.wram0[addr - WRAM0_OFF],
        .wram1 => self.wram1[addr - WRAM1_OFF],
        .echo => self.readByte(addr - ECHO_DIFF),
        .ie => @bitCast(self.ie),
    };
}
pub fn readBytes(self: Memory, addr: usize) u16 {
    const region = rangeFromAddr(addr);
    return switch (region) {
        .prohiboted => {
            return 0xFFFF;
        },
        .external_ram => std.mem.readInt(u16, &[2]u8{ self.external_ram[addr - EXTERNAL_RAM_OFF], self.external_ram[addr - EXTERNAL_RAM_OFF + 1] }, .little),
        .bank0 => {
            if (self.rom_mapped and addr - BANK0_OFF < 0x0100) {
                return std.mem.readInt(u16, BOOT_ROM[addr - BANK0_OFF ..][0..2], .little);
            }
            return std.mem.readInt(u16, self.bank0[addr - BANK0_OFF ..][0..2], .little);
        },
        .bank1 => std.mem.readInt(u16, self.bank1[addr - BANK1_OFF ..][0..2], .little),
        .vram => std.mem.readInt(u16, self.vram[addr - VRAM_OFF ..][0..2], .little),
        .oam => std.mem.readInt(u16, self.oam[addr - OAM_OFF ..][0..2], .little),
        .io => {
            std.log.warn("IO is not implemented yet", .{});
            return 0;
        },
        .hram => std.mem.readInt(u16, self.hram[addr - HRAM_OFF ..][0..2], .little),
        .wram0 => std.mem.readInt(u16, self.wram0[addr - WRAM0_OFF ..][0..2], .little),
        .wram1 => std.mem.readInt(u16, self.wram1[addr - WRAM1_OFF ..][0..2], .little),
        .echo => self.readBytes(addr - ECHO_DIFF),
        .ie => @panic("cant read ie as a u16"),
    };
}
pub fn writeByte(self: *Memory, addr: usize, val: u8) void {
    const region = rangeFromAddr(addr);
    switch (region) {
        .prohiboted => {
            std.log.warn("writing to prohiboted memory region: {X:0<4}", .{addr});
        },
        .external_ram => self.external_ram[addr - EXTERNAL_RAM_OFF] = val,
        .bank0 => {
            std.log.warn("tried to write to ROM lol", .{});
        },
        .bank1 => {
            std.log.warn("tried to write to ROM lol", .{});
        },
        .vram => self.vram[addr - VRAM_OFF] = val,
        .wram0 => self.wram0[addr - WRAM0_OFF] = val,
        .wram1 => self.wram1[addr - WRAM1_OFF] = val,
        .oam => self.oam[addr - OAM_OFF] = val,
        .io => self.ioWriteByte(addr, val),
        .hram => self.hram[addr - HRAM_OFF] = val,
        .echo => self.writeByte(addr - ECHO_DIFF, val),
        .ie => self.ie = @bitCast(val),
    }
}
pub fn writeBytes(self: *Memory, addr: usize, val: u16) void {
    const region = rangeFromAddr(addr);
    //std.log.debug("writing {X:0<4} to: {}", .{val, region});
    switch (region) {
        .prohiboted => {
            std.log.warn("writing to prohiboted memory region: {X:0<4}", .{addr});
        },
        .bank0 => {
            std.log.warn("tried to write to ROM lol", .{});
        },
        .bank1 => {
            std.log.warn("tried to write to ROM lol", .{});
        },
        .vram => std.mem.writeInt(u16, self.vram[addr - VRAM_OFF ..][0..2], val, .little),
        .oam => std.mem.writeInt(u16, self.oam[addr - OAM_OFF ..][0..2], val, .little),
        .io => std.log.warn("IO not implemented yet", .{}),
        .hram => std.mem.writeInt(u16, self.hram[addr - HRAM_OFF ..][0..2], val, .little),
        .external_ram => std.mem.writeInt(u16, self.external_ram[addr - EXTERNAL_RAM_OFF ..][0..2], val, .little),
        .wram0 => std.mem.writeInt(u16, self.wram0[addr - WRAM0_OFF ..][0..2], val, .little),
        .wram1 => std.mem.writeInt(u16, self.wram1[addr - WRAM1_OFF ..][0..2], val, .little),
        .echo => self.writeBytes(addr - ECHO_DIFF, val),
        .ie => @panic("cant write u16 to ie"),
    }
}

const IE = packed struct { vblank: bool, lcd: bool, timer: bool, serial: bool, joypad: bool, _padding: u3 };

const IF_OFF = 0xFF0F;

const IF = packed struct { vblank: bool, stat: bool, timer: bool, serial: bool, joypad: bool, _padding: u3 };

const STAT_OFF = 0xFF41;
const STAT = packed struct {
    ppu_mode: enum(u2) {
        hblank = 0,
        vblank = 1,
        oam_scan = 2,
        drawing = 3,
    },
    lyc_eq_ly: bool,
    mode_0_select: bool,
    mode_1_select: bool,
    mode_2_select: bool,
    lyc_select: bool,
    _padding: u1,
};

const SCY_OFF = 0xFF42;
const SCX_OFF = 0xFF43;

const SB_OFF = 0xFF01;
const SC_OFF = 0xFF02;

const LCDC_OFF = 0xFF40;
const LCDC = packed struct {
    bg_window_enable: bool,
    obj_enable: bool,
    obj_size: u1,
    bg_tile_map_area: u1,
    bg_window_tile_data_area: u1,
    window_enable: bool,
    window_tile_map_area: u1,
    lcd_ppu_enable: bool,
};

const LY_OFF = 0xFF44;

const TIMA_OFF = 0xFF05;

const TMA_OFF = 0xFF06;

const TAC_OFF = 0xFF07;
const TAC = packed struct {
    clock_select: u2,
    enable: bool,
    _pdding: u5,
    pub fn getHz(tac: TAC) usize {
        return switch (tac.clock_select) {
            0b00 => 4096,
            0b01 => 262144,
            0b10 => 65536,
            0b11 => 16384,
        };
    }
};

const LYC_OFF = 0xFF45;

const BGP_OFF = 0xFF47;
const BGP = packed struct {
    id0: u2,
    id1: u2,
    id2: u2,
    id3: u2,
    pub fn get(self: BGP, n: usize) u2 {
        return switch (n) {
            0 => self.id0,
            1 => self.id1,
            2 => self.id2,
            3 => self.id3,
            else => unreachable,
        };
    }
};

const OBP = packed struct {
    _padding: u2,
    id1: u2,
    id2: u2,
    id3: u2,
    pub fn get(self: OBP, n: usize) u2 {
        return switch (n) {
            1 => self.id1,
            2 => self.id2,
            3 => self.id3,
            else => unreachable,
        };
    }
};
const OBP0_OFF = 0xFF48;
const OBP1_OFF = 0xFF49;

const WY_OFF = 0xFF4A;
const WX_OFF = 0xFF4B;

const JOYP = packed struct {
    a_right: bool,
    b_left: bool,
    select_up: bool,
    start_down: bool,
    dpad: bool,
    buttons: bool,
    _padding: u2,
};
const JOYP_OFF = 0xFF00;

const DIV_OFF = 0xFF04;

const OAM_DMA_TRANSFER_OFF = 0xFF46;

const IoRegs = struct {
    DIV: u8,
    JOYP: JOYP,
    IF: IF,
    STAT: STAT,
    SCX: u8,
    SCY: u8,
    LCDC: LCDC,
    LY: u8,
    LYC: u8,
    TIMA: u8,
    TMA: u8,
    TAC: TAC,
    BGP: BGP,
    OBP0: OBP,
    OBP1: OBP,
    WX: u8,
    WY: u8,
};

const log_checking = false;
fn ioReadByte(mem: Memory, addr: usize) u8 {
    switch (addr) {
        IF_OFF => {
            return @bitCast(mem.io.IF);
        },
        SCY_OFF => {
            return mem.io.SCY;
        },
        SCX_OFF => {
            return mem.io.SCX;
        },
        STAT_OFF => {
            return @bitCast(mem.io.STAT);
        },
        SB_OFF => {
            std.log.warn("Serial Transfer is not implemented :(", .{});
            return 0x00;
        },
        SC_OFF => {
            std.log.warn("Serial Transfer is not implemented :(", .{});
            return 0x00;
        },
        LCDC_OFF => {
            return @bitCast(mem.io.LCDC);
        },
        LY_OFF => {
            return mem.io.LY;
        },
        TIMA_OFF => {
            return mem.io.TIMA;
        },
        TMA_OFF => {
            return mem.io.TMA;
        },
        TAC_OFF => {
            return @bitCast(mem.io.TAC);
        },
        LYC_OFF => {
            return mem.io.LYC;
        },
        BGP_OFF => {
            return @bitCast(mem.io.BGP);
        },
        OBP0_OFF => {
            return @bitCast(mem.io.OBP0);
        },
        OBP1_OFF => {
            return @bitCast(mem.io.OBP1);
        },
        JOYP_OFF => {
            var joyp: JOYP = @bitCast(@as(u8, 0xFF));
            if (mem.io.JOYP.buttons and mem.io.JOYP.dpad) return 0xFF;
            if (!mem.io.JOYP.dpad) {
                joyp.a_right = !rl.IsKeyDown(rl.KEY_RIGHT);
                joyp.b_left = !rl.IsKeyDown(rl.KEY_LEFT);
                joyp.select_up = !rl.IsKeyDown(rl.KEY_UP);
                joyp.start_down = !rl.IsKeyDown(rl.KEY_DOWN);
            } else if (!mem.io.JOYP.buttons) {
                joyp.a_right = !rl.IsKeyDown(rl.KEY_A);
                joyp.b_left = !rl.IsKeyDown(rl.KEY_B);
                joyp.select_up = !rl.IsKeyDown(rl.KEY_E);
                joyp.start_down = !rl.IsKeyDown(rl.KEY_S);
            } else {
                return 0x00;
            }
            return @bitCast(joyp);
        },
        DIV_OFF => {
            return mem.io.DIV;
        },
        0xFF10...0xFF26 => {
            return 0x0;
        },
        else => {
            std.log.warn("unknown IO address: {X:0>4}", .{addr});
            return 0xFF;
        },
    }
}
fn ioWriteByte(mem: *Memory, addr: usize, val: u8) void {
    return switch (addr) {
        IF_OFF => {
            const v: IF = @bitCast(val);
            mem.io.IF = v;
        },
        SCY_OFF => {
            mem.io.SCY = val;
        },
        SCX_OFF => {
            mem.io.SCX = val;
        },
        STAT_OFF => {
            const v: STAT = @bitCast(val );
            mem.io.STAT.lyc_select = v.lyc_select;
            mem.io.STAT.mode_0_select = v.lyc_select;
            mem.io.STAT.mode_1_select = v.lyc_select;
            mem.io.STAT.mode_2_select = v.lyc_select;
        },
        SB_OFF => {
            mem.sb_data = val;
        },
        SC_OFF => {
            if (val == 0x81) std.io.getStdOut().writeAll(&.{mem.sb_data}) catch unreachable;
            mem.sb_data = 0;
        },
        LCDC_OFF => {
            const v: LCDC = @bitCast(val);
            std.log.info("setting LCDC to {}", .{v});
            mem.io.LCDC = v;
        },
        LY_OFF => std.log.warn("trying to write to LY which is read only", .{}),
        TIMA_OFF => {
            std.log.info("setting TIMA to {}", .{val});
            mem.io.TIMA = val;
        },
        TMA_OFF => {
            std.log.info("setting TMA to {}", .{val});
            mem.io.TMA = val;
        },
        LYC_OFF => {
            std.log.info("setting LYC to {}", .{val});
            mem.io.LYC = val;
        },
        BGP_OFF => {
            const v: BGP = @bitCast(val);
            std.log.info("setting BGP to {}", .{v});
            mem.io.BGP = v;
        },
        OBP0_OFF => {
            const v: OBP = @bitCast(val);
            std.log.info("setting OBP0 to {}", .{v});
            mem.io.OBP0 = v;
        },
        OBP1_OFF => {
            const v: OBP = @bitCast(val);
            std.log.info("setting OBP1 to {}", .{v});
            mem.io.OBP1 = v;
        },
        WY_OFF => {
            std.log.info("setting WY to {}", .{val});
            mem.io.WY = val;
        },
        WX_OFF => {
            std.log.info("setting WX to {}", .{val});
            mem.io.WX = val;
        },
        JOYP_OFF => {
            const v: JOYP = @bitCast(val & 0b00110000);
            std.log.info("setting JOYP to {}", .{v});
            mem.io.JOYP = v;
        },
        DIV_OFF => {
            mem.io.DIV = 0x00;
        },
        TAC_OFF => {
            const v: TAC = @bitCast(val);
            std.log.info("setting TAC to {}", .{v});
            mem.io.TAC = v;
        },
        OAM_DMA_TRANSFER_OFF => {
            const v16: u16 = @intCast(val);
            const start = v16 * 0x100;
            std.log.info("starting OAM trasfer from src: {X:0>4}", .{start});
            mem.oam_transfer_data = .{ .src_start = start };
        },
        0xFF50 => {
            if (mem.rom_mapped) mem.rom_mapped = false;
            std.log.debug("--- ROM UNMAPPED ---", .{});
            std.time.sleep(std.time.ns_per_s * 0.5);
        },
        0xFF7F => {},
        0xFF10...0xFF26 => {},
        else => std.log.warn("unknown IO address: {X:0<4}", .{addr}),
    };
}

pub fn getTileMapAddr(mem: Memory, idx: u8) u16 {
    //std.debug.print("idx: {}\n", .{idx});
    switch (mem.io.LCDC.bg_window_tile_data_area) {
        0 => {
            const idx_i: i8 = @bitCast(idx);
            const idx_ib: i16 = @intCast(idx_i);
            return @intCast(@as(i32, 0x9000) + idx_ib * 16);
        },
        1 => {
            const idx_b: u16 = @intCast(idx);
            return @as(u16, 0x8000) + idx_b * 16;
        },
    }
}
