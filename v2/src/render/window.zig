// Placeholder for window management
// Will be expanded with proper window handling

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const Window = struct {
    handle: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,
    width: i32,
    height: i32,

    pub fn init(title: [*:0]const u8, width: i32, height: i32) !Window {
        const handle = c.SDL_CreateWindow(
            title,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            width,
            height,
            c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        );
        if (handle == null) return error.WindowFailed;

        const renderer = c.SDL_CreateRenderer(handle, -1, c.SDL_RENDERER_SOFTWARE);
        if (renderer == null) {
            c.SDL_DestroyWindow(handle);
            return error.RendererFailed;
        }

        return Window{
            .handle = handle,
            .renderer = renderer,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: *Window) void {
        if (self.renderer) |r| c.SDL_DestroyRenderer(r);
        if (self.handle) |w| c.SDL_DestroyWindow(w);
    }
};
