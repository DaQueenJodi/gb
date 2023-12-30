const std = @import("std");
const GB = @import("gameboy");
const Ppu = GB.Ppu;
const Cpu = GB.Cpu;
const execNextInstruction = GB.execNextInstruction;
const Cart = GB.Cart;

const SCREEN_WIDTH = 144;
const SCREEN_HEIGHT = 160;

pub const std_options = struct {
    pub const log_level: std.log.Level = .info;
};

const c = @cImport({
    @cInclude("raylib.h");
});

const KiB = 1024;

const CART_IMAGE = @embedFile("roms/1.gb");

pub fn main() !void {
    try testing();
}

pub fn main1() !void {

    c.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "gb");
    defer c.CloseWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cpu = try Cpu.create(allocator);
    defer cpu.deinit(allocator);
    @memcpy(&cpu.mem.bank0, CART_IMAGE[0..16*KiB]);
    @memcpy(&cpu.mem.bank1, CART_IMAGE[16*KiB..]);

    var ppu = Ppu{};

    const cart = Cart.init(CART_IMAGE);
    if (true) {
        std.debug.print("name: {s}\n", .{cart.name});
        std.debug.print("rom size: {}\n", .{cart.rom_size});
        std.debug.print("ram size: {}\n", .{cart.ram_size});
        std.debug.print("is japanese?: {}\n", .{cart.is_japanese});
        std.debug.print("flavor: {}\n", .{cart.flavor});
    }

    var timer = try std.time.Timer.start();
    while (true) {
        const cycles = execNextInstruction(&cpu);
        for (0..cycles) |_| {
            ppu.tick(cpu.mem);
        }
        if (ppu.dots_count == 70224) {
            ppu.resetFrame(cpu.mem);


            if (true) {
                c.BeginDrawing();
                for (0..SCREEN_HEIGHT) |y| {
                    for (0..SCREEN_WIDTH) |x| {
                        const col = switch (Ppu.FB[y*SCREEN_WIDTH+x]) {
                            .transparent => c.Color{.a = 0},
                            .white => c.WHITE,
                            .black => c.BLACK,
                            .dark_grey => c.DARKGRAY,
                            .light_grey => c.LIGHTGRAY
                        };
                        c.DrawPixel(@intCast(x), @intCast(y), col);
                    }
                }
                c.EndDrawing();
            }

            const elapsed = timer.read();
            const TARGET: u64 = std.time.ns_per_ms * 16.7;
            //const elapsed_f: f32 = @floatFromInt(elapsed);
            //const elapsed_ms = elapsed_f / std.time.ns_per_ms;
            //try std.io.getStdOut().writer().print("took {}ms to draw the frame, target was {}ms\n", .{elapsed_ms, 16.7});
            if (elapsed < TARGET) {
                std.time.sleep(TARGET - elapsed);
            }
            timer.reset();
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
        if (addr < 0x4000) {
            mem.bank0[addr] = @intCast(r[1]);
        } else if (addr < 0x8000) {
            mem.bank1[addr - 0x4000] = @intCast(r[1]);
        } else {
            mem.writeByte(addr, @intCast(r[1]));
        }
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
fn cmpCpuConfig(cpu: Cpu, config: Config) void {
    inline for (REG_TABLE) |r| {
        //std.log.info("comparing: {s}", .{r.u});
        assert(cpu.regs.get(r.u) == @field(config, r.l));
    }
    for (config.ram) |r| {
        const addr = r[0];
        assert(cpu.mem.readByte(addr) == r[1]);
    }
}

fn readFile(alloc: Allocator, path: []const u8) ![]const u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    const stat = try f.stat();
    const buf = try alloc.alloc(u8, stat.size);
    _ = try f.readAll(buf);
    return buf;
}

pub fn testing() !void  {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const json = try readFile(alloc, "tests/jsmoo/00.json");
    const tests = try std.json.parseFromSliceLeaky([]Test, alloc, json, .{ .ignore_unknown_fields = true });
    for (tests, 0..) |te, i| {
        var cpu = try configToCpu(alloc, te.initial);
        assert(execNextInstruction(&cpu) == te.cycles.len * 4);
        cmpCpuConfig(cpu, te.final);
        std.log.info("passed test #{}", .{i});
    }
}
