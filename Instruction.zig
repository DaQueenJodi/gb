const std = @import("std");

const Instruction = @This();

pub const InstructionFlavor = enum {
    NOP,
    JP
};

const Register = enum { A, F, B, C, D, E, H, L, AF, BC, DE, HL, SP, PC };

pub const Operand = union(enum) {
    reg_direct: Register,
    reg_indirect: Register,
    immediate8,
    immediate16,
    address8,
    address16,
    add_pc,
};

const MAX_OPERANDS_LEN = 4;

const Operands = struct {
    arr: [MAX_OPERANDS_LEN]Operand = undefined,
    len: usize,
};

flavor: InstructionFlavor,
operands: Operands = .{.len = 0},

