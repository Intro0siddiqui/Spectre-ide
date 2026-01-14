// Spectre-IDE v2 - Standalone GUI with TUI design
// Main entry point

const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const Window = @import("render/window.zig");
const TextRenderer = @import("render/text.zig");

pub fn main() !void {
    // Initialize SDL2
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.debug.print("SDL2 init failed\n", .{});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window
    const window = c.SDL_CreateWindow(
        "Spectre-IDE",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        1280,
        720,
        c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
    );
    if (window == null) {
        std.debug.print("Window creation failed\n", .{});
        return error.WindowFailed;
    }
    defer c.SDL_DestroyWindow(window);

    // Create software renderer (CPU rendering)
    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_SOFTWARE);
    if (renderer == null) {
        std.debug.print("Renderer creation failed\n", .{});
        return error.RendererFailed;
    }
    defer c.SDL_DestroyRenderer(renderer);

    // Main loop
    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        // Handle events
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_QUIT) {
                running = false;
            }
            if (event.type == c.SDL_KEYDOWN) {
                if (event.key.keysym.sym == c.SDLK_q and
                    (event.key.keysym.mod & c.KMOD_CTRL) != 0)
                {
                    running = false;
                }
            }
        }

        // Clear screen with Dracula background
        _ = c.SDL_SetRenderDrawColor(renderer, 40, 42, 54, 255); // #282a36
        _ = c.SDL_RenderClear(renderer);

        // TODO: Render text grid here

        // Present
        c.SDL_RenderPresent(renderer);

        // Cap at ~60 FPS
        c.SDL_Delay(16);
    }

    std.debug.print("Goodbye!\n", .{});
}
