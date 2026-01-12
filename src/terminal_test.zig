const std = @import("std");
const terminal = @import("terminal.zig");
const testing = std.testing;

const syscalls = @import("syscalls.zig");

test "CommandRelay Spawn and Capture" {
    var relay = terminal.CommandRelay.init();
    // Use simple command
    try relay.spawn("/bin/echo Hello");
    
    // Give it a moment to run
    syscalls.msleep(10);

    var buf: [64]u8 = undefined;
    const len = relay.readOutput(&buf);
    
    try testing.expect(len > 0);
    // echo might output "Hello\n" or just "Hello"
    try testing.expectEqualStrings("Hello\n", buf[0..len]);
    
    relay.kill();
}

