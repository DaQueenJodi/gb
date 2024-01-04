const std = @import("std");
const Allocator = std.mem.Allocator;
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    c.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "gb");
    defer c.CloseWindow();

    var ppu = Ppu{};
    var timer = Timer{};
    var cpu = try Cpu.create(allocator);
    defer cpu.deinit(allocator);


    const file = args[1];
    const cart_image = try readFile(allocator, file);

    @memcpy(cpu.mem.bank0[0..], cart_image[0..0x4000]);
    @memcpy(cpu.mem.bank1[0..], cart_image[0x4000..]);

    const cart = Cart.init(cart_image);
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
            ppu.handleLCDInterrupts(cpu.mem);
            if (cpu.handleInterupts()) cycles += 20;
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
            ppu.fetcher.window_line_counter = 0;
            if (true) {
                c.BeginDrawing();
                for (0..SCREEN_HEIGHT) |y| {
                    for (0..SCREEN_WIDTH) |x| {
                        @setRuntimeSafety(false);
                        const col = switch (Ppu.FB[y * SCREEN_WIDTH + x]) {
                            .transparent => @panic("hi"),
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
                try std.io.getStdOut().writer().print("took {}ms to draw the frame, target was {}ms\n", .{ elapsed_ms, 16.7 });
            }
            if (elapsed < TARGET) {
                std.time.sleep(TARGET - elapsed);
            }
            frame_timer.reset();
        }
        const orig: u8 = @bitCast(cpu.mem.io.JOYP);
        const joyp = &cpu.mem.io.JOYP;
        if (!joyp.dpad) {
            joyp.a_right = !c.IsKeyDown(c.KEY_RIGHT);
            joyp.b_left = !c.IsKeyDown(c.KEY_LEFT);
            joyp.select_up = !c.IsKeyDown(c.KEY_UP);
            joyp.start_down = !c.IsKeyDown(c.KEY_DOWN);
        } 
        if (!joyp.buttons) {
            joyp.a_right = !c.IsKeyDown(c.KEY_A);
            joyp.b_left = !c.IsKeyDown(c.KEY_B);
            joyp.select_up = !c.IsKeyDown(c.KEY_E);
            joyp.start_down = !c.IsKeyDown(c.KEY_S);
        }

        const new: u8 = @bitCast(cpu.mem.io.JOYP);
        // if a bit was reset
        if (new & orig < orig) {
            cpu.mem.io.IF.joypad = true;
        }
    }

    std.process.cleanExit();
}



fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();

    const stat = try f.stat();
    const size = stat.size;

    const buf = try allocator.alloc(u8, size);
    _ = try f.readAll(buf);
    return buf;
}
