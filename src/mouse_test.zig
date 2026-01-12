const std = @import("std");
const mouse = @import("mouse.zig");
const testing = std.testing;

test "Parse SGR Mouse Click" {
    // \x1b[<0;20;10M -> Button 0 (Left), Col 20, Row 10, Pressed
    const event = mouse.parseSgrMouse("\x1b[<0;20;10M");
    try testing.expect(event != null);
    try testing.expectEqual(@as(u8, 0), event.?.button);
    try testing.expectEqual(@as(usize, 20), event.?.col);
    try testing.expectEqual(@as(usize, 10), event.?.row);
    try testing.expectEqual(true, event.?.pressed);
}

test "Parse SGR Mouse Release" {
    // \x1b[<0;20;10m -> Button 0 (Left), Col 20, Row 10, Released
    const event = mouse.parseSgrMouse("\x1b[<0;20;10m");
    try testing.expect(event != null);
    try testing.expectEqual(false, event.?.pressed);
}
