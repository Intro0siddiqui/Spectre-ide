const std = @import("std");
const ansi_mouse = @import("ansi_mouse.zig");
const testing = std.testing;

test "ANSI Mouse Constants" {
    try testing.expectEqualStrings("\x1b[?1000h", ansi_mouse.ENABLE_X11_MOUSE);
    try testing.expectEqualStrings("\x1b[?1000l", ansi_mouse.DISABLE_X11_MOUSE);
    try testing.expectEqualStrings("\x1b[?1006h", ansi_mouse.ENABLE_SGR_MOUSE);
    try testing.expectEqualStrings("\x1b[?1006l", ansi_mouse.DISABLE_SGR_MOUSE);
}
