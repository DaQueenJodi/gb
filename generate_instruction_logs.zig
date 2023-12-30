const std = @import("std");

const base = @embedFile("instructions.zig");

const OperandFlavor = union(enum) {
    reg: []const u8,
    d8,
    d16,
    r8,
    a8,
    pub fn fromStr(s: []const u8) OperandFlavor {
        if (std.mem.eql(u8, s, "d8")) return .d8;
        if (std.mem.eql(u8, s, "a8")) return .a8;
        if (std.mem.eql(u8, s, "d16")) return .d16;
        if (std.mem.eql(u8, s, "a16")) return .d16;
        if (std.mem.eql(u8, s, "r8")) return .r8;
        return .{ .reg = s };
    }
};
const Operand = struct {
    flavor: OperandFlavor,
    indirect: bool,
    pub fn fromStr(s: []const u8) Operand {
        const indirect = s[0] == '(' and s[s.len - 1] == ')';
        const actual_operand = if (indirect) s[1 .. s.len - 1] else s;
        const flavor = OperandFlavor.fromStr(actual_operand);
        return .{
            .flavor = flavor,
            .indirect = indirect,
        };
    }
};

const Instruction = struct {
    opcode: []const u8,
    operands: []Operand,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    const out_file = args[1];

    const base_lines_count = std.mem.count(u8, base, "\n");
    var logs = try allocator.alloc(?Instruction, base_lines_count);
    for (logs) |*l| l.* = null;

    var base_it = std.mem.tokenizeScalar(u8, base, '\n');
    var line_index: usize = 0;
    while (base_it.next()) |line| : (line_index += 1) {
        const stripped_line = std.mem.trim(u8, line, " ");
        // look for comments
        if (!std.mem.startsWith(u8, stripped_line, "// ")) continue;
        const inst_line = stripped_line["// ".len..];
        // check if the next line is in the form '0xNN => {'
        const next_line = base_it.peek() orelse break;
        if (!nexLineIsRight(next_line)) continue;

        var inst_line_it = std.mem.tokenizeAny(u8, inst_line, " ,");
        var inst_operands_container: [3]Operand = undefined;

        const opcode = inst_line_it.next() orelse std.debug.panic("{s}", .{line});
        var inst_operands_index: usize = 0;
        while (inst_line_it.next()) |operand_str| : (inst_operands_index += 1) {
            inst_operands_container[inst_operands_index] = Operand.fromStr(operand_str);
        }
        const inst = Instruction{
            .opcode = opcode,
            .operands = try allocator.dupe(Operand, inst_operands_container[0..inst_operands_index]),
        };
        logs[line_index] = inst;
    }
    base_it.reset();
    line_index = 0;
    var f = try std.fs.cwd().createFile(out_file, .{});
    defer f.close();
    const writer = f.writer();
    while (base_it.next()) |line| : (line_index += 1) {
        try writer.writeAll(line);
        try writer.writeByte('\n');
        if (line_index < 1) continue;
        const log_maybe = logs[line_index - 1];
        if (log_maybe) |log| {
            try writeLogLine(writer, log);
        }
    }

    std.process.cleanExit();
}

fn writeLogLine(writer: anytype, log: Instruction) !void {
    try writer.writeAll("std.debug.print(\"{X:0>4}: ");
    try writer.writeAll(log.opcode);
    try writer.writeAll(" ");
    for (log.operands, 0..) |operand, i| {
        if (i != 0) {
            try writer.writeAll(", ");
        }
        const str = switch (operand.flavor) {
            .reg => |s| s,
            .a8 => "${X:0>4}",
            .d8 => "${X:0>2}",
            .d16 => "${X:0>4}",
            .r8 => "{X:0>2}",
        };
        if (operand.indirect) {
            try writer.print("({s})", .{str});
        } else {
            try writer.writeAll(str);
        }
    }

    try writer.writeAll("\\n\", .{cpu.regs.get(\"PC\")-1,");
    for (log.operands) |operand| {
        const str = switch (operand.flavor) {
            .reg => |_| "",
            .a8 => "0xFF00 + @as(u16, @intCast(cpu.peakByte())),",
            .d8 => "cpu.peakByte(),",
            .d16 => "cpu.peakBytes(),",
            .r8 => "cpu.peakSignedByte(),",
        };
        try writer.writeAll(str);
    }

    try writer.writeAll("});\n");
}

// TODO: be more permissive maybe
fn nexLineIsRight(line: []const u8) bool {
    const stripped_line = std.mem.trimLeft(u8, line, " ");
    if (!std.mem.startsWith(u8, stripped_line, "0x")) return false;
    if (!std.mem.endsWith(u8, stripped_line, " => {")) return false;
    for (stripped_line["0x".len.."0xNN".len]) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}
