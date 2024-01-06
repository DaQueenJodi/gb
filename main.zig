const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const GB = @import("gameboy");
const Input = GB.Input;
const Memory = GB.Memory;
const Ppu = GB.Ppu;
const Cpu = GB.Cpu;
const Timer = GB.Timer;
const execNextInstruction = GB.execNextInstruction;
const Cart = GB.Cart;

const SCREEN_WIDTH = 160;
const SCREEN_HEIGHT = 144;
const SCREEN_SCALE = 1;

pub const std_options = struct {
    pub const log_level: std.log.Level = .warn;
};

pub const c = @import("c");

const KiB = 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    const window = c.SDL_CreateWindow(
        "gb",
        0,
        0,
        SCREEN_WIDTH * SCREEN_SCALE,
        SCREEN_HEIGHT * SCREEN_SCALE,
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE,
    );
    defer c.SDL_DestroyWindow(window);
    const renderer = c.SDL_CreateRenderer(
        window,
        0,
        c.SDL_RENDERER_PRESENTVSYNC | c.SDL_RENDERER_ACCELERATED,
    );
    defer c.SDL_DestroyRenderer(renderer);

    _ = c.SDL_RenderSetLogicalSize(renderer, SCREEN_WIDTH, SCREEN_HEIGHT);

    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGB24,
        c.SDL_TEXTUREACCESS_STREAMING,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
    );


    var input = Input{};
    var ppu = Ppu{};
    var timer = Timer{};
    var cpu = try Cpu.create(allocator, &input);
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
    var quit = false;

    while (!quit) {
        //c.___tracy_emit_frame_mark_start("loop");
        //defer c.___tracy_emit_frame_mark_end("loop");
        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event) != 0) {
            switch (sdl_event.type) {
                c.SDL_QUIT => quit = true,
                //c.SDL_KEYDOWN, c.SDL_KEYUP => input.handleSDLEvent(sdl_event),
                else => {},
            }
        }
        var cycles = execNextInstruction(&cpu);
        while (cycles > 0) : (cycles -= 1) {
            ppu.handleLCDInterrupts(cpu.mem);
            if (cpu.handleInterupts()) cycles += 20;
            ppu.tick(cpu.mem);
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


            var pixels: [*]u8 = undefined;
            var pitch: c_int = undefined;

            _ = c.SDL_SetRenderDrawColor(renderer, 0x00, 0x00, 0x00, 0x00);
            _ = c.SDL_RenderClear(renderer);
            _ = c.SDL_LockTexture(texture, null, @ptrCast(&pixels), &pitch);
            @memcpy(pixels, Ppu.FB[0..]);
            _ = c.SDL_UnlockTexture(texture);

            _ = c.SDL_RenderCopy(renderer, texture, null, null);
            c.SDL_RenderPresent(renderer);

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
