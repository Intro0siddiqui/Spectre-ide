const std = @import("std");
const core = @import("buffer.zig");

// Global editor instance
var editor_instance: core.Editor = undefined;
var initialized = false;

export fn spectre_init() void {
    if (!initialized) {
        editor_instance = core.Editor.init();
        initialized = true;

        // Manual insertion for safety if file loading is complex
        const msg = "// Spectre-IDE Hybrid Mode\n";
        for (msg) |c| {
            editor_instance.insertChar(c);
        }
    }
}

export fn spectre_insert_char(c: u8) void {
    editor_instance.insertChar(c);
}

export fn spectre_delete_char(backspace: bool) void {
    editor_instance.deleteChar(backspace);
}

export fn spectre_move(op: c_int) void {
    // 0: Up, 1: Down, 2: Left, 3: Right
    switch (op) {
        0 => editor_instance.moveCursor(.up),
        1 => editor_instance.moveCursor(.down),
        2 => editor_instance.moveCursor(.left),
        3 => editor_instance.moveCursor(.right),
        else => {},
    }
}

export fn spectre_undo() void {
    editor_instance.undo();
}

// Data Access for GUI
export fn spectre_get_cursor_row() usize {
    return editor_instance.cursor_row;
}

export fn spectre_get_cursor_col() usize {
    return editor_instance.cursor_col;
}

export fn spectre_get_line_count() usize {
    const buf = editor_instance.buffer_manager.getCurrent() orelse return 0;
    if (buf.data == null) return 0;

    var count: usize = 0;
    for (0..buf.file_size) |i| {
        if (buf.data.?[i] == '\n') count += 1;
    }
    return count + 1;
}

// Basic way to get line content for rendering.
// caller must provide buffer.
export fn spectre_get_line_content(row: usize, out_ptr: [*]u8, max_len: usize) usize {
    const buf = editor_instance.buffer_manager.getCurrent() orelse return 0;
    if (buf.data == null) return 0;

    var byte_offset: usize = 0;
    var current_row: usize = 0;

    while (current_row < row) : (current_row += 1) {
        while (byte_offset < buf.file_size and buf.data.?[byte_offset] != '\n') : (byte_offset += 1) {}
        byte_offset += 1;
    }

    if (byte_offset >= buf.file_size) return 0;

    var i: usize = 0;
    while (i < max_len and byte_offset + i < buf.file_size and buf.data.?[byte_offset + i] != '\n') : (i += 1) {
        out_ptr[i] = buf.data.?[byte_offset + i];
    }
    out_ptr[i] = 0; // Null terminate
    return i;
}
