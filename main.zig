const std = @import("std");
const GB = @import("gameboy");
const Ppu = GB.Ppu;
const Cpu = GB.Cpu;
const Timer = GB.Timer;
const execNextInstruction = GB.execNextInstruction;
const Cart = GB.Cart;

const SCREEN_WIDTH = 160;
const SCREEN_HEIGHT = 144;

pub const std_options = struct {
    pub const log_level: std.log.Level = .warn;
};

pub const c = @import("c.zig");

const KiB = 1024;

const CART_IMAGE = @embedFile("roms/Tetris.gb");

pub fn main() !void {
    c.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "gb");
    defer c.CloseWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ppu = Ppu{};
    var timer = Timer{};
    var cpu = try Cpu.create(allocator);
    defer cpu.deinit(allocator);
    @memcpy(cpu.mem.bank0[0..], CART_IMAGE[0..0x4000]);
    @memcpy(cpu.mem.bank1[0..], CART_IMAGE[0x4000..]);

    const cart = Cart.init(CART_IMAGE);
    if (true) {
        std.debug.print("name: {s}\n", .{cart.name});
        std.debug.print("rom size: {}\n", .{cart.rom_size});
        std.debug.print("ram size: {}\n", .{cart.ram_size});
        std.debug.print("is japanese?: {}\n", .{cart.is_japanese});
        std.debug.print("flavor: {}\n", .{cart.flavor});
    }

    var frame_timer = try std.time.Timer.start();
    while (!c.WindowShouldClose()) {
        var cycles = execNextInstruction(&cpu);
        while (cycles > 0) : (cycles -= 1) {
            cycles += cpu.handleInterupts();
            try ppu.tick(cpu.mem);
            timer.tick(cpu.mem);
            if (cpu.mem.oam_transfer_data) |d| {
                if (d.cycle == 160) {
                    cpu.mem.oam_transfer_data = null;
                    continue;
                }
                const s = cpu.mem.readByte(d.src_start + d.cycle);
                cpu.mem.writeByte(0xFE00 + d.cycle, s);
                cpu.mem.oam_transfer_data.?.cycle += 1;
            }
        }
        if (ppu.just_finished) {
            ppu.just_finished = false;

            if (true) {
                c.BeginDrawing();
                c.ClearBackground(c.WHITE);
                for (0..SCREEN_HEIGHT) |y| {
                    for (0..SCREEN_WIDTH) |x| {
                        const col = switch (Ppu.FB[y * SCREEN_WIDTH + x]) {
                            .transparent => c.Color{ .a = 0 },
                            .white => c.WHITE,
                            .black => c.BLACK,
                            .dark_grey => c.DARKGRAY,
                            .light_grey => c.LIGHTGRAY,
                        };
                        c.DrawPixel(@intCast(x), @intCast(y), col);
                    }
                }
                c.EndDrawing();
            }

            const elapsed = frame_timer.read();
            const TARGET: u64 = std.time.ns_per_ms * 16.7;
            if (false) {
                const elapsed_f: f32 = @floatFromInt(elapsed);
                const elapsed_ms = elapsed_f / std.time.ns_per_ms;
                try std.io.getStdOut().writer().print("took {}ms to draw the frame, target was {}ms\n", .{elapsed_ms, 16.7});
            }
            if (elapsed < TARGET) {
                std.time.sleep(TARGET - elapsed);
            }
            frame_timer.reset();
        }
    }

    std.process.cleanExit();
}

const Allocator = std.mem.Allocator;
const Registers = GB.Registers;
const Memory = GB.Memory;

const assert = std.debug.assert;

const Config = struct {
    pc: u16,
    sp: u16,
    a: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    f: u8,
    h: u8,
    l: u8,
    ime: u1,
    ram: [][2]u16,
};

const Test = struct {
    name: []const u8,
    initial: Config,
    final: Config,
    cycles: []std.json.Value,
};

const REG_TABLE = [_]struct { l: []const u8, u: []const u8 }{
    .{ .l = "a", .u = "A" },
    .{ .l = "b", .u = "B" },
    .{ .l = "c", .u = "C" },
    .{ .l = "d", .u = "D" },
    .{ .l = "e", .u = "E" },
    .{ .l = "f", .u = "F" },
    .{ .l = "h", .u = "H" },
    .{ .l = "l", .u = "L" },
    .{ .l = "sp", .u = "SP" },
    .{ .l = "pc", .u = "PC" },
};
// TOOD: ie
fn configToCpu(allocator: Allocator, config: Config) !Cpu {
    var mem = try allocator.create(Memory);
    mem.rom_mapped = false;

    // TODO: desmellify this
    for (config.ram) |r| {
        const addr = r[0];
        mem.writeByte(addr, @intCast(r[1]));
    }

    var regs: Registers = undefined;
    inline for (REG_TABLE) |r| {
        regs.set(r.u, @field(config, r.l));
    }
    regs.ime = config.ime == 1;

    return Cpu{
        .ime_scheduled = false,
        .mem = mem,
        .regs = regs,
    };
}

fn cmpCpuConfig(cpu: Cpu, config: Config) bool {
    inline for (REG_TABLE) |r| {
        if (cpu.regs.get(r.u) != @field(config, r.l)) {
            std.log.err("register {s} should be {X} but is {X}!", .{
                r.u, @field(config, r.l), cpu.regs.get(r.u),
            });
            return false;
        }
    }
    for (config.ram) |r| {
        const addr = r[0];
        if (cpu.mem.readByte(addr) != r[1]) {
            std.log.err("memory address {X:0>4} should be {X:0>2} but is {X:0>2}!", .{
                addr, r[1], cpu.mem.readByte(addr),
            });
            return false;
        }
    }
    return true;
}

fn readFile(alloc: Allocator, path: []const u8) ![]const u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    const stat = try f.stat();
    const buf = try alloc.alloc(u8, stat.size);
    _ = try f.readAll(buf);
    return buf;
}

const TEST_FILES_COUNT = 498;
const TEST_FILE_PATHS: [TEST_FILES_COUNT][]const u8 = blk: {
    var arr: [TEST_FILES_COUNT][]const u8 = undefined;
    var arr_i: usize = 0;
    // opcodes that dont exist
    const exceptions = [12]u8{
        0xD3, 0xE3, 0xE4, 0xF4, 0xDB, 0xEB, 0xEC, 0xFC, 0xFD, 0xED, 0xDD, 0xCB
    };
    for (0..0xFF) |b| {
        if (std.mem.indexOfScalar(u8, &exceptions, b) == null)
        {
            arr[arr_i] = std.fmt.comptimePrint("tests/jsmoo/{x:0>2}.json.zst", .{b});
            arr_i += 1;
        }
    }
    // CB prefixed
    for (0..0xFF) |b| {
        arr[arr_i] = std.fmt.comptimePrint("tests/jsmoo/cb {x:0>2}.json.zst", .{b});
        arr_i += 1;
    }
    break :blk arr;
};

fn testFailed(test_nr: usize, check_nr: usize) !void {
    std.log.err("TEST {} FAILED AT CHECK {}!", .{ test_nr, check_nr });
    const f = try std.fs.cwd().createFile("failed_test", .{});
    defer f.close();

    const writer = f.writer();
    try writer.writeInt(usize, test_nr, .little);

    std.process.exit(1);
}

fn test_last_failed() !usize {
    const f = std.fs.cwd().openFile("failed_test", .{}) catch {
        return 0;
    };
    defer f.close();

    const reader = f.reader();
    const test_nr = try reader.readInt(usize, .little);
    return test_nr;
}

fn testing() !void {
    const test_nr = try test_last_failed();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    for (TEST_FILE_PATHS, 0..) |path, t_i| {
        if (t_i < test_nr) continue;
        std.debug.print("{s}\n", .{path});
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        var decompressed_stream = std.compress.zstd.decompressStream(alloc, file.reader());
        defer decompressed_stream.deinit();
        const json = try decompressed_stream.reader().readAllAlloc(alloc, std.math.maxInt(usize));
        const tests = try std.json.parseFromSliceLeaky([]Test, alloc, json, .{ .ignore_unknown_fields = true });
        for (tests, 0..) |te, ch_i| {
            var cpu = try configToCpu(alloc, te.initial);
            const cycles = execNextInstruction(&cpu);
            // special case for STOP and HALT
            if (cycles != te.cycles.len * 4 and t_i != 0x10 and t_i != 0x76) {
                std.log.err("took {} cycles when it should have taken {}!", .{
                    cycles, te.cycles.len * 4,
                });
                try testFailed(t_i, ch_i);
            }
            if (!cmpCpuConfig(cpu, te.final)) {
                try testFailed(t_i, ch_i);
            }
        }

        _ = arena.reset(.retain_capacity);
        std.debug.print("passed: {}!\n", .{t_i});
    }
    std.debug.print("passed {} tests!", .{TEST_FILES_COUNT - test_nr});
}
