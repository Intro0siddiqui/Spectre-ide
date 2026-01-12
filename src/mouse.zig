pub const MouseEvent = struct {
    button: u8,
    col: usize,
    row: usize,
    pressed: bool,
};

pub fn parseSgrMouse(buffer: []const u8) ?MouseEvent {
    if (buffer.len < 6 or buffer[0] != 0x1b or buffer[1] != '[' or buffer[2] != '<') return null;

    var i: usize = 3;
    
    // Parse button
    var button: usize = 0;
    while (i < buffer.len and buffer[i] >= '0' and buffer[i] <= '9') : (i += 1) {
        button = button * 10 + (buffer[i] - '0');
    }

    if (i >= buffer.len or buffer[i] != ';') return null;
    i += 1;

    // Parse col
    var col: usize = 0;
    while (i < buffer.len and buffer[i] >= '0' and buffer[i] <= '9') : (i += 1) {
        col = col * 10 + (buffer[i] - '0');
    }

    if (i >= buffer.len or buffer[i] != ';') return null;
    i += 1;

    // Parse row
    var row: usize = 0;
    while (i < buffer.len and buffer[i] >= '0' and buffer[i] <= '9') : (i += 1) {
        row = row * 10 + (buffer[i] - '0');
    }

    if (i >= buffer.len) return null;
    
    const char = buffer[i];
    if (char != 'M' and char != 'm') return null;

    return MouseEvent{
        .button = @as(u8, @intCast(button)),
        .col = col,
        .row = row,
        .pressed = (char == 'M'),
    };
}