const std = @import("std");

const Cpu = @import("hardware").Cpu;

/// returns the number of clock cycles it should take to execute
pub fn exec(cpu: *Cpu, opcode: u8) usize {
    switch (opcode) {
        // NOP
        0x00 => {
            return 4;
        },
        // JP a16
        0xC3 => {
            cpu.jp(cpu.nextBytes());
            return 16;
        },
        // XOR A
        0xAF => {
            cpu.xor(cpu.regs.get("A"));
            return 4;
        },
        // LD HL, d16
        0x21 => {
            cpu.regs.set("HL", cpu.nextBytes());
            return 12;
        },
        // LD C, d8
        0x0E => {
            cpu.regs.set("C", cpu.nextByte());
            return 8;
        },
        // LD B, d8
        0x06 => {
            cpu.regs.set("B", cpu.nextByte());
            return 8;
        },
        // LD (HL-), A
        0x32 => {
            const hl = cpu.regs.get("HL");
            cpu.mem.writeByte(hl, cpu.regs.get("A"));
            cpu.regs.set("HL", hl -% 1);
            return 8;
        },
        // DEC B
        0x05 => {
            cpu.dec("B");
            return 4;
        },
        // JR NZ, r8
        0x20 => {
            const n: i8 = @intCast(cpu.nextSignedByte());
            const pc_i: i32 = @intCast(cpu.regs.pc);
            if (!cpu.regs.get_z()) {
                cpu.jp(@intCast(pc_i + n));
                return 12;
            } else return 8;
        },
        // RRA
        0x1F => {
            cpu.rr("A");
            cpu.regs.set_z(false);
            return 4;
        },
        // DEC H
        0x25 => {
            cpu.dec("H");
            return 4;
        },
        // DEC C
        0x0D => {
            cpu.dec("C");
            return 4;
        },
        // LD A, d8
        0x3E => {
            cpu.regs.set("A", cpu.nextByte());
            return 8;
        },
        // DI
        0xF3 => {
            cpu.ime_scheduled = false;
            cpu.regs.ime = false;
            return 4;
        },
        // LDH (a8), A
        0xE0 => {
            const off: u16 = @intCast(cpu.nextByte());
            const addr: u16 = off + 0xFF00;
            cpu.mem.writeByte(addr, cpu.regs.get("A"));
            return 12;
        },
        // LDH A, (a8)
        0xF0 => {
            const off: u16 = @intCast(cpu.nextByte());
            const addr: u16 = off + 0xFF00;
            const val = cpu.mem.readByte(addr);
            cpu.regs.set("A", val);
            return 12;
        },
        // CP d8
        0xFE => {
            cpu.cp(cpu.nextByte());
            return 8;
        },
        // LD (HL), d8
        0x36 => {
            const n = cpu.nextByte();
            const addr = cpu.regs.get("HL");
            cpu.mem.writeByte(addr, n);
            return 12;
        },
        // LD (d16), A
        0xEA => {
            const a = cpu.regs.get("A");
            const addr = cpu.nextBytes();
            cpu.mem.writeByte(addr, a);
            return 16;
        },
        // LD SP, d16
        0x31 => {
            cpu.regs.set("SP", cpu.nextBytes());
            return 12;
        },
        // LD A, (HL+)
        0x2A => {
            const hl = cpu.regs.get("HL");
            cpu.regs.set("A", cpu.mem.readByte(hl));
            cpu.regs.set("HL", hl +% 1);
            return 8;
        },
        // LD (FF00+C), A
        0xE2 => {
            const c = cpu.regs.get("C");
            const addr: u16 = @as(u16, 0xFF00) +% c;
            cpu.mem.writeByte(addr, cpu.regs.get("A"));
            return 8;
        },
        // INC C
        0x0C => {
            cpu.inc("C");
            return 4;
        },
        // CALL d16
        0xCD => {
            const addr = cpu.nextBytes();
            cpu.call(addr);
            return 24;
        },
        // SUB L
        0x95 => {
            cpu.sub(cpu.regs.get("L"));
            return 4;
        },
        // DAA
        0x27 => {
            const src = cpu.regs.get("A");
            var correction: u8 = 0;
            const h = cpu.regs.get_h();
            const n = cpu.regs.get_n();
            const c = cpu.regs.get_c();
            if (h or (!n and (src & 0x0F) > 0x09)) {
                correction |= 0x06;
            }
            if (c or (!n and (src & 0xFF) > 0x99)) {
                correction |= 0x60;
                cpu.regs.set_c(true);
            }

            const new = if (!n) src +% correction else src -% correction;

            cpu.regs.set("A", new);
            cpu.regs.set_h(false);
            cpu.regs.set_z(new == 0);

            return 4;
        },
        // LD A, A
        0x7F => {
            return 4;
        },
        // EI
        0xFB => {
            cpu.ime_scheduled = true;
            return 4;
        },
        // AND (HL)
        0xA6 => {
            const n = cpu.mem.readByte(cpu.regs.get("HL"));
            const res = cpu.regs.get("A") & n;
            cpu.regs.set("A", res);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(true);
            cpu.regs.set_c(false);
            return 8;
        },
        // ADD HL, HL
        0x29 => {
            cpu.add16(cpu.regs.get("HL"));
            return 8;
        },
        0xCB => {
            return prefixed(cpu, cpu.nextByte());
        },
        // LD (HL), A
        0x77 => {
            cpu.mem.writeByte(cpu.regs.get("HL"), cpu.regs.get("A"));
            return 8;
        },
        // LD DE, d16
        0x11 => {
            cpu.regs.set("DE", cpu.nextBytes());
            return 12;
        },
        // LD A, (DE)
        0x1A => {
            cpu.regs.set("A", cpu.mem.readByte(cpu.regs.get("DE")));
            return 8;
        },
        // SUB (HL)
        0x96 => {
            cpu.sub(cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // INC DE
        0x13 => {
            cpu.regs.set("DE", cpu.regs.get("DE") +% 1);
            return 8;
        },
        // LD A, E
        0x7B => {
            cpu.regs.set("A", cpu.regs.get("E"));
            return 4;
        },
        // LD (HL+), A
        0x22 => {
            cpu.mem.writeByte(cpu.regs.get("HL"), cpu.regs.get("A"));
            cpu.regs.set("HL", cpu.regs.get("HL") +% 1);
            return 8;
        },
        // INC HL
        0x23 => {
            cpu.regs.set("HL", cpu.regs.get("HL") +% 1);
            return 8;
        },
        // DEC A
        0x3D => {
            cpu.dec("A");
            return 4;
        },
        // JR Z, r8
        0x28 => {
            const n: i8 = @intCast(cpu.nextSignedByte());
            if (cpu.regs.get_z()) {
                const neg = n < 0;
                const n_a = @abs(n);
                const pc = cpu.regs.get("PC");
                const addr = if (neg) pc -% n_a else pc +% n_a;
                cpu.jp(addr);
                return 12;
            }
            return 8;
        },
        // LD L, d8
        0x2E => {
            cpu.regs.set("L", cpu.nextByte());
            return 8;
        },
        // JR r8
        0x18 => {
            const n: i8 = @intCast(cpu.nextSignedByte());
            const neg = n < 0;
            const n_a = @abs(n);
            const pc = cpu.regs.get("PC");
            const addr = if (neg) pc -% n_a else pc +% n_a;
            cpu.jp(addr);
            return 12;
        },
        // LD H, A
        0x67 => {
            cpu.regs.set("H", cpu.regs.get("A"));
            return 4;
        },
        // LD D, A
        0x57 => {
            cpu.regs.set("D", cpu.regs.get("A"));
            return 4;
        },
        // INC B
        0x04 => {
            cpu.inc("B");
            return 4;
        },
        // LD E, d8
        0x1E => {
            cpu.regs.set("E", cpu.nextByte());
            return 8;
        },
        // DEC E
        0x1D => {
            cpu.dec("E");
            return 4;
        },
        // INC H
        0x24 => {
            cpu.inc("H");
            return 4;
        },
        // LD A, H
        0x7C => {
            cpu.regs.set("A", cpu.regs.get("H"));
            return 4;
        },
        // SUB B
        0x90 => {
            cpu.sub(cpu.regs.get("B"));
            return 4;
        },
        // DEC D
        0x15 => {
            cpu.dec("D");
            return 4;
        },
        // CP A, (HL)
        0xBE => {
            cpu.cp(cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // LD B, A
        0x47 => {
            cpu.regs.set("B", cpu.regs.get("A"));
            return 4;
        },
        // LD (DE), A
        0x12 => {
            cpu.mem.writeByte(cpu.regs.get("DE"), cpu.regs.get("A"));
            return 8;
        },
        // INC E
        0x1C => {
            cpu.inc("E");
            return 4;
        },
        // INC D
        0x14 => {
            cpu.inc("D");
            return 4;
        },
        // LD A, B
        0x78 => {
            cpu.regs.set("A", cpu.regs.get("B"));
            return 4;
        },
        // SUB E
        0x93 => {
            cpu.sub(cpu.regs.get("E"));
            return 4;
        },
        // RET NZ
        0xC0 => {
            if (!cpu.regs.get_z()) {
                const addr = cpu.popBytes();
                cpu.regs.set("PC", addr);
                return 20;
            }
            return 8;
        },
        // LD A, (HL)
        0x7E => {
            cpu.regs.set("A", cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // POP BC
        0xC1 => {
            cpu.regs.set("BC", cpu.popBytes());
            return 12;
        },
        // LD C, A
        0x4F => {
            cpu.regs.set("C", cpu.regs.get("A"));
            return 4;
        },
        // PUSH AF
        0xF5 => {
            cpu.pushBytes(cpu.regs.get("AF"));
            return 16;
        },
        // INC BC
        0x03 => {
            cpu.regs.set("BC", cpu.regs.get("BC") +% 1);
            return 8;
        },
        // POP AF
        0xF1 => {
            cpu.regs.set("AF", cpu.popBytes());
            // clear padding bits
            const f = cpu.regs.get("F");
            cpu.regs.set("F", f & 0xF0);
            return 12;
        },
        // XOR H
        0xAC => {
            cpu.xor(cpu.regs.get("H"));
            return 4;
        },
        // CALL NZ, d16
        0xC4 => {
            const addr = cpu.nextBytes();
            if (!cpu.regs.get_z()) {
                cpu.call(addr);
                return 24;
            }
            return 12;
        },
        // LD A, L
        0x7D => {
            cpu.regs.set("A", cpu.regs.get("L"));
            return 4;
        },
        // RET
        0xC9 => {
            cpu.jp(cpu.popBytes());
            return 16;
        },
        // PUSH HL
        0xE5 => {
            cpu.pushBytes(cpu.regs.get("HL"));
            return 16;
        },
        // POP HL
        0xE1 => {
            cpu.regs.set("HL", cpu.popBytes());
            return 12;
        },
        // LD L, B
        0x68 => {
            cpu.regs.set("L", cpu.regs.get("B"));
            return 4;
        },
        // LD L, E
        0x6B => {
            cpu.regs.set("L", cpu.regs.get("E"));
            return 4;
        },
        // LD C, L
        0x4D => {
            cpu.regs.set("C", cpu.regs.get("L"));
            return 4;
        },
        // PUSH BC
        0xC5 => {
            cpu.pushBytes(cpu.regs.get("BC"));
            return 16;
        },
        // LD BC, d16
        0x01 => {
            cpu.regs.set("BC", cpu.nextBytes());
            return 12;
        },
        // OR C
        0xB1 => {
            cpu.or_(cpu.regs.get("C"));
            return 4;
        },
        // LD A, (d16)
        0xFA => {
            cpu.regs.set("A", cpu.mem.readByte(cpu.nextBytes()));
            return 16;
        },
        // AND d8
        0xE6 => {
            cpu.and_(cpu.nextByte());
            return 8;
        },
        // INC L
        0x2C => {
            cpu.inc("L");
            return 4;
        },
        // XOR C
        0xA9 => {
            cpu.xor(cpu.regs.get("C"));
            return 4;
        },
        // ADD d8
        0xC6 => {
            cpu.add(cpu.nextByte());
            return 8;
        },
        // SUB d8
        0xD6 => {
            cpu.sub(cpu.nextByte());
            return 8;
        },
        // OR A
        0xB7 => {
            // basically a no-op but does set Z
            cpu.or_(cpu.regs.get("A"));
            return 4;
        },
        // PUSH DE
        0xD5 => {
            cpu.pushBytes(cpu.regs.get("DE"));
            return 16;
        },
        // LD B, (HL)
        0x46 => {
            cpu.regs.set("B", cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // DEC L
        0x2D => {
            cpu.dec("L");
            return 4;
        },
        // LD C, (HL)
        0x4E => {
            cpu.regs.set("C", cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // LD D, (HL)
        0x56 => {
            cpu.regs.set("D", cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // XOR (HL)
        0xAE => {
            cpu.xor(cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // LD H, d8
        0x26 => {
            cpu.regs.set("H", cpu.nextByte());
            return 8;
        },
        // ADD HL, DE
        0x19 => {
            cpu.add16(cpu.regs.get("DE"));
            return 8;
        },
        // JR NC, a8
        0x30 => {
            const n = cpu.nextSignedByte();
            if (!cpu.regs.get_c()) {
                const pc_i: i32 = @intCast(cpu.regs.get("PC"));
                cpu.jp(@intCast(pc_i + n));
                return 12;
            }
            return 8;
        },
        // LD E, a
        0x5F => {
            cpu.regs.set("E", cpu.regs.get("A"));
            return 4;
        },
        // XOR d8
        0xEE => {
            cpu.xor(cpu.nextByte());
            return 8;
        },
        // LD A, C
        0x79 => {
            cpu.regs.set("A", cpu.regs.get("C"));
            return 4;
        },
        // LD A, D
        0x7A => {
            cpu.regs.set("A", cpu.regs.get("D"));
            return 4;
        },
        // LD (HL), D
        0x72 => {
            cpu.mem.writeByte(cpu.regs.get("HL"), cpu.regs.get("D"));
            return 8;
        },
        // LD (HL), C
        0x71 => {
            cpu.mem.writeByte(cpu.regs.get("HL"), cpu.regs.get("C"));
            return 8;
        },
        // LD (HL), B
        0x70 => {
            cpu.mem.writeByte(cpu.regs.get("HL"), cpu.regs.get("B"));
            return 8;
        },
        // POP DE
        0xD1 => {
            cpu.regs.set("DE", cpu.popBytes());
            return 12;
        },
        // ADC d8
        0xCE => {
            cpu.adc(cpu.nextByte());
            return 8;
        },
        // RET NC
        0xD0 => {
            if (!cpu.regs.get_c()) {
                cpu.jp(cpu.popBytes());
                return 20;
            }
            return 8;
        },
        // RET Z
        0xC8 => {
            if (cpu.regs.get_z()) {
                cpu.jp(cpu.popBytes());
                return 20;
            }
            return 8;
        },
        // OR (HL)
        0xB6 => {
            cpu.or_(cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // DEC (HL)
        0x35 => {
            const n = cpu.mem.readByte(cpu.regs.get("HL"));
            const res = n -% 1;
            cpu.mem.writeByte(cpu.regs.get("HL"), res);
            cpu.regs.set_n(true);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_h(Cpu.subHalfCarry8(n, 1));
            return 12;
        },
        // LD L, (HL)
        0x6E => {
            cpu.regs.set("L", cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // LD E, D
        0x5A => {
            cpu.regs.set("E", cpu.regs.get("D"));
            return 4;
        },
        // LD L, A
        0x6F => {
            cpu.regs.set("L", cpu.regs.get("A"));
            return 4;
        },
        // JP HL
        0xE9 => {
            cpu.jp(cpu.regs.get("HL"));
            return 4;
        },
        // INC A
        0x3C => {
            cpu.inc("A");
            return 4;
        },
        // JP NZ, d16
        0xC2 => {
            const addr = cpu.nextBytes();
            if (!cpu.regs.get_z()) {
                cpu.jp(addr);
                return 16;
            }
            return 12;
        },
        // CP A, E
        0xBB => {
            cpu.cp(cpu.regs.get("E"));
            return 4;
        },
        // RET C
        0xD8 => {
            if (cpu.regs.get_c()) {
                cpu.jp(cpu.popBytes());
                return 20;
            }
            return 8;
        },
        // JR C, a8
        0x38 => {
            const n = cpu.nextSignedByte();
            if (cpu.regs.get_c()) {
                const pc_i: i32 = @intCast(cpu.regs.get("PC"));
                cpu.jp(@intCast(pc_i + n));
                return 12;
            }
            return 8;
        },
        // CPL
        0x2F => {
            cpu.regs.set("A", cpu.regs.get("A") ^ 0xFF);
            cpu.regs.set_n(true);
            cpu.regs.set_h(true);
            return 4;
        },
        // LD E, L
        0x5D => {
            cpu.regs.set("E", cpu.regs.get("L"));
            return 4;
        },
        // DEC DE
        0x1B => {
            cpu.regs.set("DE", cpu.regs.get("DE") -% 1);
            return 8;
        },
        // LD (HL), E
        0x73 => {
            cpu.mem.writeByte(cpu.regs.get("HL"), cpu.regs.get("E"));
            return 8;
        },
        // LD E, (HL)
        0x5E => {
            cpu.regs.set("E", cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // LD (d16), SP
        0x08 => {
            cpu.mem.writeBytes(cpu.nextBytes(), cpu.regs.get("SP"));
            return 20;
        },
        // LD H, (HL)
        0x66 => {
            cpu.regs.set("H", cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // LD SP, HL
        0xF9 => {
            cpu.regs.set("SP", cpu.regs.get("HL"));
            return 8;
        },
        // LD H, D
        0x62 => {
            cpu.regs.set("H", cpu.regs.get("D"));
            return 4;
        },
        // INC SP
        0x33 => {
            cpu.regs.set("SP", cpu.regs.get("SP") +% 1);
            return 8;
        },
        // XOR L
        0xAD => {
            cpu.xor(cpu.regs.get("L"));
            return 4;
        },
        // OR B
        0xB0 => {
            cpu.or_(cpu.regs.get("B"));
            return 4;
        },
        // DEC SP
        0x3B => {
            cpu.regs.set("SP", cpu.regs.get("SP") -% 1);
            return 8;
        },
        // ADD HL, SP
        0x39 => {
            const z = cpu.regs.get_z();
            cpu.add16(cpu.regs.get("SP"));
            cpu.regs.set_z(z);
            return 8;
        },
        // ADD SP, r8
        0xE8 => {
            const n: i8 = cpu.nextSignedByte();
            const n16: i16 = @intCast(n);
            const sp = cpu.regs.get("SP");
            const sp_i: i32 = @intCast(sp);
            const res_32: u32 = @bitCast(sp_i +% n16);
            const res: u16 = @truncate(res_32);
            cpu.regs.set("SP", res);
            cpu.regs.set_z(false);
            cpu.regs.set_n(false);
            cpu.regs.set_h(Cpu.addHalfCarry8(@truncate(sp), @bitCast(n)));
            cpu.regs.set_c((@as(u8, @truncate(sp)) > @as(u8, @truncate(res))));
            return 16;
        },
        // LD HL, SP+r8
        0xF8 => {
            const n: i8 = cpu.nextSignedByte();
            const n16: i16 = @intCast(n);
            const sp = cpu.regs.get("SP");
            const sp_i: i32 = @intCast(sp);
            const res_32: u32 = @bitCast(sp_i +% n16);
            const res: u16 = @truncate(res_32);
            cpu.regs.set("HL", res);

            cpu.regs.set_z(false);
            cpu.regs.set_n(false);
            cpu.regs.set_h(Cpu.addHalfCarry8(@truncate(sp), @bitCast(n)));
            cpu.regs.set_c((@as(u8, @truncate(sp)) > @as(u8, @truncate(res))));
            return 12;
        },
        // SCF
        0x37 => {
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(true);
            return 4;
        },
        // LD D, d8
        0x16 => {
            cpu.regs.set("D", cpu.nextByte());
            return 8;
        },
        // OR d8
        0xF6 => {
            cpu.or_(cpu.nextByte());
            return 8;
        },
        // SBC d8
        0xDE => {
            cpu.sbc(cpu.nextByte());
            return 8;
        },
        // JP Z, d16
        0xCA => {
            const addr = cpu.nextBytes();
            if (cpu.regs.get_z()) {
                cpu.jp(addr);
                return 16;
            }
            return 12;
        },
        // JP NC, d16
        0xD2 => {
            const addr = cpu.nextBytes();
            if (!cpu.regs.get_c()) {
                cpu.jp(addr);
                return 16;
            }
            return 12;
        },
        // JP C, d16
        0xDA => {
            const addr = cpu.nextBytes();
            if (cpu.regs.get_c()) {
                cpu.jp(addr);
                return 16;
            }
            return 12;
        },
        // CALL Z, d16
        0xCC => {
            const addr = cpu.nextBytes();
            if (cpu.regs.get_z()) {
                cpu.call(addr);
                return 24;
            }
            return 12;
        },
        //  CALL NC, d16
        0xD4 => {
            const addr = cpu.nextBytes();
            if (!cpu.regs.get_c()) {
                cpu.call(addr);
                return 24;
            }
            return 12;
        },
        //
        0xDC => {
            const addr = cpu.nextBytes();
            if (cpu.regs.get_c()) {
                cpu.pushBytes(cpu.regs.get("PC"));
                cpu.jp(addr);
                return 24;
            }
            return 12;
        },
        // RETI
        0xD9 => {
            cpu.jp(cpu.popBytes());
            cpu.regs.ime = true;
            return 16;
        },
        // RST 00
        0xC7 => {
            cpu.call(0x0000);
            return 16;
        },
        // RST 08
        0xCF => {
            cpu.call(0x0008);
            return 16;
        },
        // RST 10
        0xD7 => {
            cpu.call(0x0010);
            return 16;
        },
        // RST 18
        0xDF => {
            cpu.call(0x0018);
            return 16;
        },
        // RST 20
        0xE7 => {
            cpu.call(0x0020);
            return 16;
        },
        // RST 28
        0xEF => {
            cpu.call(0x0028);
            return 16;
        },
        // RST 30
        0xF7 => {
            cpu.call(0x0030);
            return 16;
        },
        // RST 38
        0xFF => {
            cpu.call(0x0038);
            return 16;
        },
        // LD (BC), A
        0x02 => {
            cpu.mem.writeByte(cpu.regs.get("BC"), cpu.regs.get("A"));
            return 8;
        },
        // RLCA
        0x07 => {
            cpu.rlc("A");
            cpu.regs.set_z(false);
            return 4;
        },
        // ADD HL, BC
        0x09 => {
            cpu.add16(cpu.regs.get("BC"));
            return 8;
        },
        // LD A, (BC)
        0x0A => {
            cpu.regs.set("A", cpu.mem.readByte(cpu.regs.get("BC")));
            return 8;
        },
        // DEC BC
        0x0B => {
            cpu.regs.set("BC", cpu.regs.get("BC") -% 1);
            return 8;
        },
        // RRCA
        0x0F => {
            cpu.rrc("A");
            cpu.regs.set_z(false);
            return 4;
        },
        // STOP
        0x10 => {
            cpu.mode = .stop;
            return 4;
        },
        // RLA
        0x17 => {
            cpu.rl("A");
            cpu.regs.set_z(false);
            return 4;
        },
        // DEC HL
        0x2B => {
            cpu.regs.set("HL", cpu.regs.get("HL") -% 1);
            return 8;
        },
        // INC (HL)
        0x34 => {
            const n = cpu.mem.readByte(cpu.regs.get("HL"));
            const res = n +% 1;
            cpu.mem.writeByte(cpu.regs.get("HL"), res);
            cpu.regs.set_n(false);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_h(Cpu.addHalfCarry8(n, 1));
            return 12;
        },
        // LD A, (HL-)
        0x3A => {
            cpu.regs.set("A", cpu.mem.readByte(cpu.regs.get("HL")));
            cpu.regs.set("HL", cpu.regs.get("HL") -% 1);
            return 8;
        },
        // CCF
        0x3F => {
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(!cpu.regs.get_c());
            return 4;
        },
        // LD B, B
        0x40 => {
            return 4;
        },
        // LD B, C
        0x41 => {
            cpu.regs.set("B", cpu.regs.get("C"));
            return 4;
        },
        // LD B, D
        0x42 => {
            cpu.regs.set("B", cpu.regs.get("D"));
            return 4;
        },
        // LD B, E
        0x43 => {
            cpu.regs.set("B", cpu.regs.get("E"));
            return 4;
        },
        // LD B, H
        0x44 => {
            cpu.regs.set("B", cpu.regs.get("H"));
            return 4;
        },
        // LD B, L
        0x45 => {
            cpu.regs.set("B", cpu.regs.get("L"));
            return 4;
        },
        // LD C, B
        0x48 => {
            cpu.regs.set("C", cpu.regs.get("B"));
            return 4;
        },
        // LD C, C
        0x49 => {
            return 4;
        },
        // LD C, D
        0x4A => {
            cpu.regs.set("C", cpu.regs.get("D"));
            return 4;
        },
        // LD C, E
        0x4B => {
            cpu.regs.set("C", cpu.regs.get("E"));
            return 4;
        },
        // LD C, H
        0x4C => {
            cpu.regs.set("C", cpu.regs.get("H"));
            return 4;
        },
        // LD D, B
        0x50 => {
            cpu.regs.set("D", cpu.regs.get("B"));
            return 4;
        },
        // LD D, C
        0x51 => {
            cpu.regs.set("D", cpu.regs.get("C"));
            return 4;
        },
        // LD D, D
        0x52 => {
            return 4;
        },
        // LD D, E
        0x53 => {
            cpu.regs.set("D", cpu.regs.get("E"));
            return 4;
        },
        // LD D, H
        0x54 => {
            cpu.regs.set("D", cpu.regs.get("H"));
            return 4;
        },
        // LD D, L
        0x55 => {
            cpu.regs.set("D", cpu.regs.get("L"));
            return 4;
        },
        // LD E, B
        0x58 => {
            cpu.regs.set("E", cpu.regs.get("B"));
            return 4;
        },
        // LD E, C
        0x59 => {
            cpu.regs.set("E", cpu.regs.get("C"));
            return 4;
        },
        // LD E, E
        0x5B => {
            return 4;
        },
        // LD E, H
        0x5C => {
            cpu.regs.set("E", cpu.regs.get("H"));
            return 4;
        },
        // LD H, B
        0x60 => {
            cpu.regs.set("H", cpu.regs.get("B"));
            return 4;
        },
        // LD H, C
        0x61 => {
            cpu.regs.set("H", cpu.regs.get("C"));
            return 4;
        },
        // LD H, E
        0x63 => {
            cpu.regs.set("H", cpu.regs.get("E"));
            return 4;
        },
        // LD H, H
        0x64 => {
            return 4;
        },
        // LD H, L
        0x65 => {
            cpu.regs.set("H", cpu.regs.get("L"));
            return 4;
        },
        // LD L, C
        0x69 => {
            cpu.regs.set("L", cpu.regs.get("C"));
            return 4;
        },
        // LD L, D
        0x6A => {
            cpu.regs.set("L", cpu.regs.get("D"));
            return 4;
        },
        // LD L, H
        0x6C => {
            cpu.regs.set("L", cpu.regs.get("H"));
            return 4;
        },
        // LD L, L
        0x6D => {
            return 4;
        },
        // LD (HL), H
        0x74 => {
            cpu.mem.writeByte(cpu.regs.get("HL"), cpu.regs.get("H"));
            return 8;
        },
        // LD (HL), L
        0x75 => {
            cpu.mem.writeByte(cpu.regs.get("HL"), cpu.regs.get("L"));
            return 8;
        },
        // HALT
        0x76 => {
            cpu.mode = .halt;
            return 4;
        },
        // ADD B
        0x80 => {
            cpu.add(cpu.regs.get("B"));
            return 4;
        },
        // ADD C
        0x81 => {
            cpu.add(cpu.regs.get("C"));
            return 4;
        },
        // ADD D
        0x82 => {
            cpu.add(cpu.regs.get("D"));
            return 4;
        },
        // ADD E
        0x83 => {
            cpu.add(cpu.regs.get("E"));
            return 4;
        },
        // ADD H
        0x84 => {
            cpu.add(cpu.regs.get("H"));
            return 4;
        },
        // ADD L
        0x85 => {
            cpu.add(cpu.regs.get("L"));
            return 4;
        },
        // ADD (HL)
        0x86 => {
            cpu.add(cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // ADD A
        0x87 => {
            cpu.add(cpu.regs.get("A"));
            return 4;
        },
        // ADC B
        0x88 => {
            cpu.adc(cpu.regs.get("B"));
            return 4;
        },
        // ADC C
        0x89 => {
            cpu.adc(cpu.regs.get("C"));
            return 4;
        },
        // ADC D
        0x8A => {
            cpu.adc(cpu.regs.get("D"));
            return 4;
        },
        // ADC E
        0x8B => {
            cpu.adc(cpu.regs.get("E"));
            return 4;
        },
        // ADC H
        0x8C => {
            cpu.adc(cpu.regs.get("H"));
            return 4;
        },
        // ADC L
        0x8D => {
            cpu.adc(cpu.regs.get("L"));
            return 4;
        },
        // ADC HL
        0x8E => {
            cpu.adc(cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // ADC A
        0x8F => {
            cpu.adc(cpu.regs.get("A"));
            return 4;
        },
        // SUB C
        0x91 => {
            cpu.sub(cpu.regs.get("C"));
            return 4;
        },
        // SUB D
        0x92 => {
            cpu.sub(cpu.regs.get("D"));
            return 4;
        },
        // SUB H
        0x94 => {
            cpu.sub(cpu.regs.get("H"));
            return 4;
        },
        // SUB A
        0x97 => {
            cpu.sub(cpu.regs.get("A"));
            return 4;
        },
        // SBC B
        0x98 => {
            cpu.sbc(cpu.regs.get("B"));
            return 4;
        },
        // SBC C
        0x99 => {
            cpu.sbc(cpu.regs.get("C"));
            return 4;
        },
        // SBC D
        0x9A => {
            cpu.sbc(cpu.regs.get("D"));
            return 4;
        },
        // SBC E
        0x9B => {
            cpu.sbc(cpu.regs.get("E"));
            return 4;
        },
        // SBC H
        0x9C => {
            cpu.sbc(cpu.regs.get("H"));
            return 4;
        },
        // SBC L
        0x9D => {
            cpu.sbc(cpu.regs.get("L"));
            return 4;
        },
        // SBC (HL)
        0x9E => {
            cpu.sbc(cpu.mem.readByte(cpu.regs.get("HL")));
            return 8;
        },
        // SBC A
        0x9F => {
            cpu.sbc(cpu.regs.get("A"));
            return 4;
        },
        // AND B
        0xA0 => {
            cpu.and_(cpu.regs.get("B"));
            return 4;
        },
        // AND C
        0xA1 => {
            cpu.and_(cpu.regs.get("C"));
            return 4;
        },
        // AND D
        0xA2 => {
            cpu.and_(cpu.regs.get("D"));
            return 4;
        },
        // AND E
        0xA3 => {
            cpu.and_(cpu.regs.get("E"));
            return 4;
        },
        // AND H
        0xA4 => {
            cpu.and_(cpu.regs.get("H"));
            return 4;
        },
        // AND L
        0xA5 => {
            cpu.and_(cpu.regs.get("L"));
            return 4;
        },
        // AND A
        0xA7 => {
            cpu.and_(cpu.regs.get("A"));
            return 4;
        },
        // XOR B
        0xA8 => {
            cpu.xor(cpu.regs.get("B"));
            return 4;
        },
        // XOR D
        0xAA => {
            cpu.xor(cpu.regs.get("D"));
            return 4;
        },
        // XOR E
        0xAB => {
            cpu.xor(cpu.regs.get("E"));
            return 4;
        },
        // OR D
        0xB2 => {
            cpu.or_(cpu.regs.get("D"));
            return 4;
        },
        // OR E
        0xB3 => {
            cpu.or_(cpu.regs.get("E"));
            return 4;
        },
        // OR H
        0xB4 => {
            cpu.or_(cpu.regs.get("H"));
            return 4;
        },
        // OR L
        0xB5 => {
            cpu.or_(cpu.regs.get("L"));
            return 4;
        },
        // CP B
        0xB8 => {
            cpu.cp(cpu.regs.get("B"));
            return 4;
        },
        // CP C
        0xB9 => {
            cpu.cp(cpu.regs.get("C"));
            return 4;
        },
        // CP D
        0xBA => {
            cpu.cp(cpu.regs.get("D"));
            return 4;
        },
        // CP H
        0xBC => {
            cpu.cp(cpu.regs.get("H"));
            return 4;
        },
        // CP L
        0xBD => {
            cpu.cp(cpu.regs.get("L"));
            return 4;
        },
        // CP A
        0xBF => {
            cpu.cp(cpu.regs.get("A"));
            return 4;
        },
        // LD A, (FF00+C)
        0xF2 => {
            const addr: u16 = @as(u16, 0xFF00) + cpu.regs.get("C");
            cpu.regs.set("A", cpu.mem.readByte(addr));
            return 8;
        },
        else => std.debug.panic("invalid opcode: {X:0>2}", .{opcode}),
    }
}

fn prefixed(cpu: *Cpu, opcode: u8) usize {
    switch (opcode) {
        // RR D
        0x1A => {
            cpu.rr("D");
            return 8;
        },
        // SRL B
        0x38 => {
            cpu.srl("B");
            return 8;
        },
        // RR C
        0x19 => {
            cpu.rr("C");
            return 8;
        },
        // RR E
        0x1B => {
            cpu.rr("E");
            return 8;
        },
        // SWAP A
        0x37 => {
            const a = cpu.regs.get("A");
            const low = a & 0x0F;
            const high = (a & 0xF0) >> 4;
            const new = (low << 4) + high;
            cpu.regs.set("A", new);
            cpu.regs.set_z(new == 0);
            cpu.regs.set_c(false);
            cpu.regs.set_h(false);
            cpu.regs.set_n(false);
            return 8;
        },
        // RLC B
        0x00 => {
            cpu.rlc("B");
            return 8;
        },
        // RLC C
        0x01 => {
            cpu.rlc("C");
            return 8;
        },
        // RLC D
        0x02 => {
            cpu.rlc("D");
            return 8;
        },
        // RLC E
        0x03 => {
            cpu.rlc("E");
            return 8;
        },
        // RLC H
        0x04 => {
            cpu.rlc("H");
            return 8;
        },
        // RLC L
        0x05 => {
            cpu.rlc("L");
            return 8;
        },
        // RLC (HL)
        0x06 => {
            const addr = cpu.regs.get("HL");
            const orig = cpu.mem.readByte(addr);
            const masked: u8 = orig & (0x01 << 7);
            const b7: u1 = @intCast(masked >> 7);
            const shifted = orig << 1;
            const res = (shifted | b7);
            cpu.mem.writeByte(addr, res);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(b7 == 1);
            return 16;
        },
        // RLC A
        0x07 => {
            cpu.rlc("A");
            return 8;
        },
        // RRC B
        0x08 => {
            cpu.rrc("B");
            return 8;
        },
        // RRC C
        0x09 => {
            cpu.rrc("C");
            return 8;
        },
        // RRC D
        0x0A => {
            cpu.rrc("D");
            return 8;
        },
        // RRC E
        0x0B => {
            cpu.rrc("E");
            return 8;
        },
        // RRC H
        0x0C => {
            cpu.rrc("H");
            return 8;
        },
        // RRC L
        0x0D => {
            cpu.rrc("L");
            return 8;
        },
        // RRC (HL)
        0x0E => {
            const addr = cpu.regs.get("HL");
            const orig = cpu.mem.readByte(addr);
            const b0: u8 = @intCast(orig & 0x01);
            const shifted = orig >> 1;
            const res = (shifted | (b0 << 7));
            cpu.mem.writeByte(addr, res);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(b0 == 1);
            return 16;
        },
        // RRC A
        0x0F => {
            cpu.rrc("A");
            return 8;
        },
        // RL B
        0x10 => {
            cpu.rl("B");
            return 8;
        },
        // RL C
        0x11 => {
            cpu.rl("C");
            return 8;
        },
        // RL D
        0x12 => {
            cpu.rl("D");
            return 8;
        },
        // RL E
        0x13 => {
            cpu.rl("E");
            return 8;
        },
        // RL H
        0x14 => {
            cpu.rl("H");
            return 8;
        },
        // RL L
        0x15 => {
            cpu.rl("L");
            return 8;
        },
        // RL (HL)
        0x16 => {
            const addr = cpu.regs.get("HL");
            const val = cpu.mem.readByte(addr);

            const c: u8 = @intFromBool(cpu.regs.get_c());
            const old_b7 = (val & (0x01 << 7)) >> 7;

            const shifted = val << 1;
            const res = shifted | c;
            cpu.mem.writeByte(addr, res);

            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(old_b7 == 1);
            return 16;
        },
        // RL A
        0x17 => {
            cpu.rl("A");
            return 8;
        },
        // RR B
        0x18 => {
            cpu.rr("B");
            return 8;
        },
        // RR H
        0x1C => {
            cpu.rr("H");
            return 8;
        },
        // RR L
        0x1D => {
            cpu.rr("L");
            return 8;
        },
        // RR (HL)
        0x1E => {
            const addr = cpu.regs.get("HL");
            const val = cpu.mem.readByte(addr);

            const c: u8 = @intFromBool(cpu.regs.get_c());
            const old_b0 = val & 0x01;

            const shifted = val >> 1;
            const res = shifted | (c << 7);
            cpu.mem.writeByte(addr, res);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(old_b0 == 1);
            return 16;
        },
        // RR A
        0x1F => {
            cpu.rr("A");
            return 8;
        },
        // SLA B
        0x20 => {
            cpu.sla("B");
            return 8;
        },
        // SLA C
        0x21 => {
            cpu.sla("C");
            return 8;
        },
        // SLA D
        0x22 => {
            cpu.sla("D");
            return 8;
        },
        // SLA E
        0x23 => {
            cpu.sla("E");
            return 8;
        },
        // SLA H
        0x24 => {
            cpu.sla("H");
            return 8;
        },
        // SLA L
        0x25 => {
            cpu.sla("L");
            return 8;
        },
        // SLA (HL)
        0x26 => {
            const addr = cpu.regs.get("HL");
            const orig = cpu.mem.readByte(addr);
            const old_b7 = (orig & (0x01 << 7)) >> 7;
            const res = orig << 1;
            cpu.mem.writeByte(addr, res);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(old_b7 == 1);
            return 16;
        },
        // SLA A
        0x27 => {
            cpu.sla("A");
            return 8;
        },

        // SRA B
        0x28 => {
            cpu.sra("B");
            return 8;
        },
        // SRA C
        0x29 => {
            cpu.sra("C");
            return 8;
        },
        // SRA D
        0x2A => {
            cpu.sra("D");
            return 8;
        },
        // SRA E
        0x2B => {
            cpu.sra("E");
            return 8;
        },
        // SRA H
        0x2C => {
            cpu.sra("H");
            return 8;
        },
        // SRA L
        0x2D => {
            cpu.sra("L");
            return 8;
        },
        // SRA (HL)
        0x2E => {
            const addr = cpu.regs.get("HL");
            const orig = cpu.mem.readByte(addr);
            const old_b7 = orig & (0x01 << 7);
            const old_b0 = orig & 0x01;
            const res = (orig >> 1) | old_b7;
            cpu.mem.writeByte(addr, res);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(old_b0 == 1);
            return 16;
        },
        // SRA A
        0x2F => {
            cpu.sra("A");
            return 8;
        },
        // SWAP B
        0x30 => {
            cpu.swap("B");
            return 8;
        },
        // SWAP C
        0x31 => {
            cpu.swap("C");
            return 8;
        },
        // SWAP D
        0x32 => {
            cpu.swap("D");
            return 8;
        },
        // SWAP E
        0x33 => {
            cpu.swap("E");
            return 8;
        },
        // SWAP H
        0x34 => {
            cpu.swap("H");
            return 8;
        },
        // SWAP L
        0x35 => {
            cpu.swap("L");
            return 8;
        },
        // SWAP (HL)
        0x36 => {
            const addr = cpu.regs.get("HL");
            const orig = cpu.mem.readByte(addr);
            const h = (orig & 0xF0) >> 4;
            const l = orig & 0x0F;
            const res = (l << 4) | h;
            cpu.mem.writeByte(addr, res);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(false);
            return 16;
        },
        // SRL C
        0x39 => {
            cpu.srl("C");
            return 8;
        },
        // SRL D
        0x3A => {
            cpu.srl("D");
            return 8;
        },
        // SRL E
        0x3B => {
            cpu.srl("E");
            return 8;
        },
        // SRL H
        0x3C => {
            cpu.srl("H");
            return 8;
        },
        // SRL L
        0x3D => {
            cpu.srl("L");
            return 8;
        },
        // SRL (HL)
        0x3E => {
            const addr = cpu.regs.get("HL");
            const orig = cpu.mem.readByte(addr);
            const old_b0 = orig & 0x01;
            const res = orig >> 1;
            cpu.mem.writeByte(addr, res);
            cpu.regs.set_z(res == 0);
            cpu.regs.set_n(false);
            cpu.regs.set_h(false);
            cpu.regs.set_c(old_b0 == 1);
            return 16;
        },
        // SRL A
        0x3F => {
            cpu.srl("A");
            return 8;
        },
        // BIT n r
        inline 0x40...0x7F => |op| {
            const off = op - 0x40;
            const bit_idx = @divFloor(off, 8);
            const operand_off = @mod(off, 8);
            const OPERAND_TABLE = [_]?[]const u8{
                "B", "C", "D", "E", "H", "L", null, "A",
            };
            if (OPERAND_TABLE[operand_off]) |r| {
                const v = cpu.regs.get(r);
                cpu.bit(v, bit_idx);
                return 8;
            } else {
                const v = cpu.mem.readByte(cpu.regs.get("HL"));
                cpu.bit(v, bit_idx);
                return 12;
            }
        },
        // RES n r
        inline 0x80...0xBF => |op| {
            const off = op - 0x80;
            const bit_idx: u3 = @divFloor(off, 8);
            const operand_off = @mod(off, 8);
            const OPERAND_TABLE = [_]?[]const u8{
                "B", "C", "D", "E", "H", "L", null, "A",
            };
            if (OPERAND_TABLE[operand_off]) |r| {
                const orig = cpu.regs.get(r);
                const mask = ~(@as(u8, 0x01) << bit_idx);
                cpu.regs.set(r, orig & mask);
                return 8;
            } else {
                const addr = cpu.regs.get("HL");
                const v = cpu.mem.readByte(addr);
                const mask = ~(@as(u8, 0x01) << bit_idx);
                cpu.mem.writeByte(addr, v & mask);
                return 16;
            }
        },
        // SET n r
        inline 0xC0...0xFF => |op| {
            const off = op - 0xC0;
            const bit_idx: u3 = @divFloor(off, 8);
            const operand_off = @mod(off, 8);
            const OPERAND_TABLE = [_]?[]const u8{
                "B", "C", "D", "E", "H", "L", null, "A",
            };
            if (OPERAND_TABLE[operand_off]) |r| {
                const orig = cpu.regs.get(r);
                const mask = @as(u8, 0x01) << bit_idx;
                cpu.regs.set(r, orig | mask);
                return 8;
            } else {
                const addr = cpu.regs.get("HL");
                const v = cpu.mem.readByte(addr);
                const mask = @as(u8, 0x01) << bit_idx;
                cpu.mem.writeByte(addr, v | mask);
                return 16;
            }
        },
    }
}
