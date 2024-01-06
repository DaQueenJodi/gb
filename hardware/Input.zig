const std = @import("std");
const Memory = @import("Memory.zig");
const assert = std.debug.assert;

const c = @import("c");

const Input = @This();

const Button = enum  {
    select,
    start,
    b,
    a,
    down,
    up,
    left,
    right,
};

button_states: std.EnumArray(Button, bool) = std.EnumArray(Button, bool).initFill(false),

pub fn handleSDLEvent(input: *Input, event: c.SDL_Event) void {
    assert(event.type == c.SDL_KEYDOWN or event.type == c.SDL_KEYUP);
    const button: Button = switch (event.key.keysym.sym) {
        c.SDLK_s => .start,
        c.SDLK_e => .select,
        c.SDLK_a => .a,
        c.SDLK_b => .b,
        c.SDLK_UP => .up,
        c.SDLK_DOWN => .down,
        c.SDLK_LEFT => .left,
        c.SDLK_RIGHT => .right,
        else => return,
    };

    switch (event.type) {
        c.SDL_KEYDOWN => input.button_states.set(button, true),
        c.SDL_KEYUP => input.button_states.set(button, false),
        else => unreachable,
    }
}
