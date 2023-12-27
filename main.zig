const std = @import("std");
const Ppu = @import("Ppu.zig");
const Cpu = @import("Cpu.zig");
const Cart = @import("Cart.zig");


const SCREEN_WIDTH = 144;
const SCREEN_HEIGHT = 160;

pub const std_options = struct {
    pub const log_level: std.log.Level = .warn;
};


const c = @cImport({
    @cInclude("raylib.h");
});

const KiB = 1024;

const CART_IMAGE = @embedFile("Tetris.gb");

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cpu = try Cpu.create(allocator);
    @memcpy(&cpu.mem.bank0, CART_IMAGE[0..16*KiB]);
    @memcpy(&cpu.mem.bank1, CART_IMAGE[16*KiB..]);

    var ppu = Ppu{};

    const cart = Cart.init(CART_IMAGE);
    std.debug.print("name: {s}\n", .{cart.name});
    std.debug.print("rom size: {}\n", .{cart.rom_size});
    std.debug.print("ram size: {}\n", .{cart.ram_size});
    std.debug.print("is japanese?: {}\n", .{cart.is_japanese});
    std.debug.print("flavor: {}\n", .{cart.flavor});

    var timer = try std.time.Timer.start();
    while (true) {
        const cycles = cpu.execNextInstruction();
        for (0..cycles) |_| {
            ppu.tick(cpu.mem);
        }
        if (ppu.dots_count == 70224) {
            ppu.resetFrame();

            const elapsed = timer.read();
            const TARGET: u64 = std.time.ns_per_ms * 16.7;
            const elapsed_f: f32 = @floatFromInt(elapsed);
            const elapsed_ms = elapsed_f / std.time.ns_per_ms;
            try std.io.getStdOut().writer().print("took {}ms to draw the frame, target was {}ms\n", .{elapsed_ms, 16.7});
            if (elapsed < TARGET) {
                std.time.sleep(TARGET - elapsed);
            }
            timer.reset();
        }
    }

    std.process.cleanExit();
}
