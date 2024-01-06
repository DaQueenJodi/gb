const build_options = @import("build_options");
pub usingnamespace @cImport({
    @cInclude("SDL2/SDL.h");
    if (build_options.tracy) {
        @cInclude("TracyC.h");
    }
});
