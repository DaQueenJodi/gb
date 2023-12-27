const std = @import("std");
const Allocator = std.mem.Allocator;

const Memory = @This();

const KiB = 1024;

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

pub fn create(allocator: Allocator) !*Memory {
    const mem = try allocator.create(Memory);

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

pub const MemRange = enum { bank0, bank1, vram, wram0, wram1, prohiboted, oam, io, hram, ie, external_ram };

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
        0xE000...0xFDFF, 0xFEA0...0xFEFF => .prohiboted,
        else => std.debug.panic("invalid range: {X:0<4}", .{addr}),
    };
}

pub fn readByte(self: Memory, addr: usize) u8 {
    const region = rangeFromAddr(addr);
    //std.log.debug("reading from: {}", .{region});
    return switch (region) {
        .prohiboted => {
            std.log.warn("reading from prohiboted memory region: {X:0<4}", .{addr});
            return 0xFF;
        },
        .external_ram => self.external_ram[addr - EXTERNAL_RAM_OFF],
        .bank0 => self.bank0[addr - BANK0_OFF],
        .bank1 => self.bank0[addr - BANK1_OFF],
        .vram => self.vram[addr - VRAM_OFF],
        .oam => self.oam[addr - OAM_OFF],
        .io => self.ioReadByte(addr),
        .hram => self.hram[addr - HRAM_OFF],
        .wram0 => self.wram0[addr - WRAM0_OFF],
        .wram1 => self.wram1[addr - WRAM1_OFF],
        .ie => @bitCast(self.ie),
    };
}
pub fn readBytes(self: Memory, addr: usize) u16 {
    const region = rangeFromAddr(addr);
    return switch (region) {
        .prohiboted => {
            std.log.warn("reading from prohiboted memory region: {X:0<4}", .{addr});
            return 0xFFFF;
        },
        .external_ram => std.mem.readInt(u16, &[2]u8{ self.external_ram[addr - EXTERNAL_RAM_OFF], self.external_ram[addr - EXTERNAL_RAM_OFF + 1] }, .little),
        .bank0 => std.mem.readInt(u16, &[2]u8{ self.bank0[addr - BANK0_OFF], self.bank0[addr - BANK0_OFF + 1] }, .little),
        .bank1 => std.mem.readInt(u16, &[2]u8{ self.bank0[addr - BANK1_OFF], self.bank0[addr - BANK1_OFF + 1] }, .little),
        .vram => std.mem.readInt(u16, &[2]u8{ self.vram[addr - VRAM_OFF], self.vram[addr - VRAM_OFF + 1] }, .little),
        .oam => std.mem.readInt(u16, &[2]u8{ self.oam[addr - OAM_OFF], self.oam[addr - OAM_OFF + 1] }, .little),
        .io => {
            std.log.err("IO is not implemented yet", .{});
            return 0;
        },
        .hram => std.mem.readInt(u16, &[2]u8{ self.hram[addr - HRAM_OFF], self.hram[addr - HRAM_OFF] }, .little),
        .wram0 => std.mem.readInt(u16, &[2]u8{ self.wram0[addr - WRAM0_OFF], self.hram[addr - WRAM0_OFF] }, .little),
        .wram1 => std.mem.readInt(u16, &[2]u8{ self.wram1[addr - WRAM1_OFF], self.hram[addr - WRAM1_OFF] }, .little),
        .ie => @panic("cant read ie as a u16"),
    };
}
pub fn writeByte(self: *Memory, addr: usize, val: u8) void {
    const region = rangeFromAddr(addr);
    //std.log.debug("writing {X:0<2} to: {}", .{val, region});
    switch (region) {
        .prohiboted => std.log.warn("writing to prohiboted memory region: {X:0<4}", .{addr}),
        .external_ram => self.external_ram[addr - EXTERNAL_RAM_OFF] = val,
        .bank0 => std.log.warn("tried to write to ROM lol", .{}),
        .bank1 => std.log.warn("tried to write to ROM lol", .{}),
        .vram => self.vram[addr - VRAM_OFF] = val,
        .wram0 => self.wram0[addr - WRAM0_OFF] = val,
        .wram1 => self.wram1[addr - WRAM1_OFF] = val,
        .oam => self.oam[addr - OAM_OFF] = val,
        .io => self.ioWriteByte(addr, val),
        .hram => self.hram[addr - HRAM_OFF] = val,
        .ie => self.ie = @bitCast(val),
    }
}
pub fn writeBytes(self: *Memory, addr: usize, val: u16) void {
    const region = rangeFromAddr(addr);
    //std.log.debug("writing {X:0<4} to: {}", .{val, region});
    switch (region) {
        .prohiboted => std.log.warn("writing to prohiboted memory region: {X:0<4}", .{addr}),
        .bank0 => std.log.warn("tried to write to ROM lol", .{}),
        .bank1 => std.log.warn("tried to write to ROM lol", .{}),
        .vram => {
            const p: *u16 = @ptrCast(&self.vram[addr - VRAM_OFF]);
            p.* = val;
        },
        .oam => {
            const p: *u16 = @ptrCast(&self.oam[OAM_OFF]);
            p.* = val;
        },
        .io => std.log.err("IO not implemented yet", .{}),
        .hram => {
            const p: *u16 = @ptrCast(&self.hram[addr - HRAM_OFF]);
            p.* = val;
        },
        .ie => @panic("cant write u16 to ie"),
    }
}

const IE = packed struct { vblank: bool, lcd: bool, timer: bool, serial: bool, joypad: bool, _padding: u3 };

const IF_OFF = 0xFF0F;

const IF = packed struct { vblank: bool, stat: bool, timer: bool, serial: bool, joypad: bool, _padding: u3 };

const STAT_OFF = 0xFF41;
const STAT = packed struct {
    ppu_mode: u2,
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
const LCDC = packed struct { bg_window_enable: bool, obj_enable: bool, obj_size: u1, bg_tile_map_area: u1, bg_window_tile_data_area: u1, window_enable: bool, window_tile_map_area: u1, lcd_ppu_enable: bool };

const LY_OFF = 0xFF44;

const TIMA_OFF = 0xFF05;

const TMA_OFF = 0xFF06;

const TAC_OFF = 0xFF07;
const TAC = packed struct {
    clock_select: u2,
    enable: bool,
    _pdding: u5,
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
            else => unreachable
        };
    }
};

const OBP = packed struct {
    _padding: u2,
    id1: u2,
    id2: u2,
    id3: u2
};
const OBP0_OFF = 0xFF48;
const OBP1_OFF = 0xFF49;

const WY_OFF = 0xFF4A;
const WX_OFF = 0xFF4B;

const IoRegs = struct {
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

fn ioReadByte(self: Memory, addr: usize) u8 {
    return switch (addr) {
        IF_OFF => @bitCast(self.io.IF),
        SCY_OFF => self.io.SCY,
        SCX_OFF => self.io.SCX,
        STAT_OFF => @bitCast(self.io.STAT),
        SB_OFF => {
            std.log.err("Serial Transfer is not implemented :(", .{});
            return 0x00;
        },
        SC_OFF => {
            std.log.err("Serial Transfer is not implemented :(", .{});
            return 0x00;
        },
        LCDC_OFF => @bitCast(self.io.LCDC),
        LY_OFF => self.io.LY,
        TIMA_OFF => self.io.TIMA,
        TMA_OFF => self.io.TMA,
        TAC_OFF => @bitCast(self.io.TAC),
        LYC_OFF => self.io.LYC,
        BGP_OFF => @bitCast(self.io.BGP),
        OBP0_OFF => @bitCast(self.io.OBP0),
        OBP1_OFF => @bitCast(self.io.OBP1),

        else => @panic("unknown IO address"),
    };
}
fn ioWriteByte(self: *Memory, addr: usize, val: u8) void {
    return switch (addr) {
        IF_OFF => self.io.IF = @bitCast(val),
        SCY_OFF => self.io.SCY = val,
        SCX_OFF => self.io.SCX = val,
        STAT_OFF => self.io.STAT = @bitCast(val),
        SB_OFF => std.log.err("Serial Transfer is not implemented :(", .{}),
        SC_OFF => std.log.err("Serial Transfer is not implemented :(", .{}),
        LCDC_OFF => self.io.LCDC = @bitCast(val),
        LY_OFF => @panic("LY is read only"),
        TIMA_OFF => self.io.TIMA = val,
        TMA_OFF => self.io.TMA = val,
        TAC_OFF => self.io.TAC = @bitCast(val),
        LYC_OFF => self.io.LYC = val,
        BGP_OFF => self.io.BGP = @bitCast(val),
        OBP0_OFF => self.io.OBP0 = @bitCast(val),
        OBP1_OFF => self.io.OBP1 = @bitCast(val),
        WY_OFF => self.io.WY = val,
        WX_OFF => self.io.WX = val,
        0xFF10...0xFF26 => std.log.err("sound is not implemented yet :(", .{}),
        else => std.debug.panic("unknown IO address: {X:0<4}", .{addr}),
    };
}


pub fn getTileMapAddr(self: Memory, idx: u8) u16 {
    std.debug.print("idx: {}\n", .{idx});
    switch (self.io.LCDC.bg_window_tile_data_area) {
        0 => {
            const idx_i: i8 = @bitCast(idx);
            const idx_ib: i16 = @intCast(idx_i);
            return @intCast(@as(i32, 0x9000) + idx_ib*16);
        },
        1 => {
            const idx_b: u16 = @intCast(idx);
            return @as(u16, 0x8000) + idx_b*16;
        }
    }
}
