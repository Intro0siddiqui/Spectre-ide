// Text rendering with FreeType
// Renders monospace text grid

const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});

pub const TextRenderer = struct {
    // Glyph cache for fast rendering
    glyph_cache: [256]?*c.SDL_Texture,
    char_width: i32,
    char_height: i32,

    pub fn init() TextRenderer {
        return TextRenderer{
            .glyph_cache = [_]?*c.SDL_Texture{null} ** 256,
            .char_width = 10,
            .char_height = 18,
        };
    }

    pub fn deinit(self: *TextRenderer) void {
        for (&self.glyph_cache) |*tex| {
            if (tex.*) |t| {
                c.SDL_DestroyTexture(t);
                tex.* = null;
            }
        }
    }
};
