const std = @import("std");
const platform = @import("platform.zig");

pub const UNDO_BUFFER_SIZE = 256;
pub const MAX_BUFFERS = 16;
pub const VIEWPORT_ROWS = 20;

pub const Operation = struct {
    op_type: enum { insert, delete },
    position: usize, // byte offset in file
    char: u8, // character inserted/deleted
};

pub const CursorMove = enum { up, down, left, right, home, end, page_up, page_down, page_begin, page_end, word_next, word_prev, word_end };
pub const Position = struct { row: usize, col: usize };

pub const Editor = struct {
    // Current active buffer state (cached)
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    line_offset: usize = 0,

    // Global editor state
    buffer_manager: BufferManager = BufferManager.init(),

    // Command/Status state
    command_buffer: [64]u8 = undefined,
    command_len: usize = 0,
    command_mode: bool = false,
    insert_mode: bool = false,

    // Search state
    search_buffer: [64]u8 = undefined,
    search_len: usize = 0,
    search_mode: bool = false,
    search_match_offset: usize = 0,

    pub fn init() Editor {
        var self = Editor{};
        @memset(&self.command_buffer, 0);
        @memset(&self.search_buffer, 0);
        return self;
    }

    pub fn insertChar(self: *Editor, char: u8) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;

        insertCharBuffer(buf.data.?, buf.file_size, self, char);
    }

    pub fn deleteChar(self: *Editor, backspace: bool) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;

        deleteCharBuffer(buf.data.?, buf.file_size, self, backspace);
    }

    pub fn moveCursor(self: *Editor, move: CursorMove) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;
        moveCursorBuffer(buf.data.?, buf.file_size, self, move);
    }

    pub fn undo(self: *Editor) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;
        undoOperation(buf.data.?, buf, self);
    }

    pub fn splitLine(self: *Editor) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;
        splitLineBuffer(buf.data.?, buf.file_size, self);
    }

    pub fn deleteLine(self: *Editor) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;
        deleteLineBuffer(buf.data.?, buf.file_size, self);
    }

    pub fn joinLine(self: *Editor) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;
        joinLineBuffer(buf.data.?, buf.file_size, self);
    }

    pub fn gotoLine(self: *Editor, line: usize) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;

        const total_lines = getTotalLines(buf.data.?, buf.file_size);
        const target_line = if (line == 0 or line > total_lines) total_lines - 1 else line - 1;
        self.cursor_row = target_line;
        self.cursor_col = getLineLength(buf.data.?, buf.file_size, target_line);
    }

    pub fn executeSearch(self: *Editor, backward: bool) void {
        const buf = self.buffer_manager.getCurrent() orelse return;
        if (buf.data == null) return;
        executeSearchBuffer(buf.data.?, buf.file_size, self, backward);
    }

    pub fn saveFile(self: *Editor) bool {
        const buf = self.buffer_manager.getCurrent() orelse return false;
        if (buf.data == null or !buf.modified) return false;

        const res = platform.rawMsync(buf.data.?, buf.aligned_size, platform.MS_SYNC);
        if (res >= 0) {
            buf.modified = false;
            return true;
        }
        return false;
    }
};

pub const FileBuffer = struct {
    filename: [256]u8 = undefined,
    filename_len: usize = 0,
    data: ?[*]u8 = null,
    file_size: usize = 0,
    aligned_size: usize = 0,
    modified: bool = false,

    // Per-buffer cursor state
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    line_offset: usize = 0,

    undo_buffer: [UNDO_BUFFER_SIZE]Operation = undefined,
    undo_index: usize = 0,
    undo_count: usize = 0,
};

pub const BufferManager = struct {
    buffers: [MAX_BUFFERS]FileBuffer = std.mem.zeroes([MAX_BUFFERS]FileBuffer),
    count: usize = 0,
    current: usize = 0,

    pub fn init() BufferManager {
        return BufferManager{};
    }

    pub fn getCurrent(self: *BufferManager) ?*FileBuffer {
        if (self.count == 0) return null;
        return &self.buffers[self.current];
    }

    pub fn loadFile(self: *BufferManager, filename: [:0]const u8) bool {
        if (self.count >= MAX_BUFFERS) return false;

        const fd = platform.rawOpen(filename.ptr, platform.O_RDWR, 0);
        if (fd < 0) return false;

        var stat_buf: platform.Stat = undefined;
        if (platform.rawFstat(@intCast(fd), &stat_buf) < 0) {
            _ = platform.rawClose(@intCast(fd));
            return false;
        }

        const file_size = if (stat_buf.size > 0) @as(usize, @intCast(stat_buf.size)) else 1024;
        const aligned_size = platform.alignUp(file_size, platform.getPageSize());

        const mapped_ptr = platform.rawMmap(null, aligned_size, platform.PROT_READ | platform.PROT_WRITE, platform.MAP_SHARED, @intCast(fd), 0);
        _ = platform.rawClose(@intCast(fd));

        if (mapped_ptr == null) return false;

        const buf = &self.buffers[self.count];
        @memset(std.mem.asBytes(buf), 0);
        buf.data = mapped_ptr;
        buf.file_size = file_size;
        buf.aligned_size = aligned_size;

        // Copy filename
        @memcpy(buf.filename[0..filename.len], filename);
        buf.filename_len = filename.len;
        buf.filename[filename.len] = 0;

        self.count += 1;
        self.current = self.count - 1;
        return true;
    }
};

// Editing logic ported from main.zig

fn insertCharBuffer(data: [*]u8, file_size: usize, editor: *Editor, char: u8) void {
    const buf = editor.buffer_manager.getCurrent() orelse return;

    var byte_offset: usize = 0;
    var current_line: usize = 0;

    // Navigate to cursor row
    while (current_line < editor.cursor_row and byte_offset < file_size) {
        while (byte_offset < file_size and data[byte_offset] != '\n') {
            byte_offset += 1;
        }
        if (byte_offset < file_size) {
            byte_offset += 1; // Skip newline
            current_line += 1;
        }
    }

    // Navigate to cursor column
    var col: usize = 0;
    while (col < editor.cursor_col and byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
        col += 1;
    }

    if (byte_offset < file_size - 1) {
        var i: usize = file_size - 1; // Limit scan
        // FIXME: Should track actual data usage
        // Using simpler loop to avoid massive memmoves on large files for now (freestanding style)

        i = buf.file_size; // Placeholder logic from before
        while (i > byte_offset) {
            data[i] = data[i - 1];
            i -= 1;
        }
        data[byte_offset] = char;

        // Record undo
        recordOperation(buf, .{ .op_type = .insert, .position = byte_offset, .char = char });

        editor.cursor_col += 1;
        buf.modified = true;
    }
}

fn deleteCharBuffer(data: [*]u8, file_size: usize, editor: *Editor, backspace: bool) void {
    var byte_offset: usize = 0;
    var current_line: usize = 0;

    while (current_line < editor.cursor_row and byte_offset < file_size) {
        while (byte_offset < file_size and data[byte_offset] != '\n') {
            byte_offset += 1;
        }
        if (byte_offset < file_size) {
            byte_offset += 1;
            current_line += 1;
        }
    }

    var col: usize = 0;
    while (col < editor.cursor_col and byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
        col += 1;
    }

    if (backspace) {
        if (byte_offset == 0) return;
        byte_offset -= 1;
        if (data[byte_offset] == '\n') return; // Don't delete newlines yet
    }

    if (byte_offset < file_size) {
        // Capture deleted char for undo
        const deleted_char = data[byte_offset];

        var i: usize = byte_offset;
        while (i < file_size - 1) {
            data[i] = data[i + 1];
            i += 1;
        }
        data[file_size - 1] = 0;

        recordOperation(editor.buffer_manager.getCurrent().?, .{ .op_type = .delete, .position = byte_offset, .char = deleted_char });

        if (backspace and editor.cursor_col > 0) {
            editor.cursor_col -= 1;
        }
    }
}

fn splitLineBuffer(data: [*]u8, file_size: usize, editor: *Editor) void {
    const byte_offset = getByteOffset(data, file_size, editor.cursor_row, editor.cursor_col);

    if (byte_offset < file_size - 1) {
        var i: usize = file_size;
        while (i > byte_offset) {
            data[i] = data[i - 1];
            i -= 1;
        }
        data[byte_offset] = '\n';
        editor.cursor_row += 1;
        editor.cursor_col = 0;
    }
}

fn deleteLineBuffer(data: [*]u8, file_size: usize, editor: *Editor) void {
    const line_start = getByteOffset(data, file_size, editor.cursor_row, 0);
    var byte_offset: usize = line_start;
    while (byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
    }
    const line_end = byte_offset;
    const has_newline = byte_offset < file_size and data[byte_offset] == '\n';
    const delete_len = if (has_newline) line_end - line_start + 1 else line_end - line_start;

    var i: usize = line_start;
    while (i < file_size - delete_len) {
        data[i] = data[i + delete_len];
        i += 1;
    }
    while (i < file_size) {
        data[i] = 0;
        i += 1;
    }

    const total_lines = getTotalLines(data, file_size);
    if (editor.cursor_row >= total_lines and editor.cursor_row > 0) {
        editor.cursor_row -= 1;
    }
    editor.cursor_col = 0;
}

fn joinLineBuffer(data: [*]u8, file_size: usize, editor: *Editor) void {
    var byte_offset = getByteOffset(data, file_size, editor.cursor_row, 0);
    while (byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
    }

    if (byte_offset >= file_size) return; // Last line
    const newline_pos = byte_offset;

    // Shift left to remove newline
    var i: usize = newline_pos;
    while (i < file_size - 1) {
        data[i] = data[i + 1];
        i += 1;
    }
    data[file_size - 1] = 0;
}

fn executeSearchBuffer(data: [*]const u8, file_size: usize, editor: *Editor, backward: bool) void {
    if (editor.search_len == 0) return;

    const pattern = editor.search_buffer[0..editor.search_len];
    if (backward) {
        const start_offset = if (editor.search_match_offset > 0) editor.search_match_offset else file_size;
        if (searchBackward(data, file_size, pattern, start_offset)) |offset| {
            updateSearchMatch(data, file_size, editor, offset);
        } else {
            // Wrap
            if (searchBackward(data, file_size, pattern, file_size)) |offset| {
                updateSearchMatch(data, file_size, editor, offset);
            }
        }
    } else {
        if (searchForward(data, file_size, pattern, editor.search_match_offset + 1)) |offset| {
            updateSearchMatch(data, file_size, editor, offset);
        } else {
            // Wrap
            if (searchForward(data, file_size, pattern, 0)) |offset| {
                updateSearchMatch(data, file_size, editor, offset);
            }
        }
    }
}

fn updateSearchMatch(data: [*]const u8, file_size: usize, editor: *Editor, offset: usize) void {
    const pos = getPositionFromByteOffset(data, file_size, offset);
    editor.search_match_offset = offset;
    editor.cursor_row = pos.row;
    editor.cursor_col = pos.col;
}

fn searchForward(data: [*]const u8, file_size: usize, pattern: []const u8, start_offset: usize) ?usize {
    if (pattern.len == 0) return null;
    var offset = start_offset;
    while (offset < file_size - pattern.len + 1) {
        var match = true;
        for (0..pattern.len) |j| {
            if (data[offset + j] != pattern[j]) {
                match = false;
                break;
            }
        }
        if (match) return offset;
        offset += 1;
    }
    return null;
}

fn searchBackward(data: [*]const u8, file_size: usize, pattern: []const u8, start_offset: usize) ?usize {
    _ = file_size;
    if (pattern.len == 0 or start_offset < pattern.len) return null;
    var offset = start_offset -| pattern.len;
    while (true) {
        var match = true;
        for (0..pattern.len) |j| {
            if (data[offset + j] != pattern[j]) {
                match = false;
                break;
            }
        }
        if (match) return offset;
        if (offset == 0) break;
        offset -= 1;
    }
    return null;
}

fn recordOperation(buf: *FileBuffer, op: Operation) void {
    if (buf.undo_count < UNDO_BUFFER_SIZE) {
        buf.undo_buffer[buf.undo_index] = op;
        buf.undo_index = (buf.undo_index + 1) % UNDO_BUFFER_SIZE;
        buf.undo_count += 1;
    } else {
        // Overwrite oldest
        buf.undo_buffer[buf.undo_index] = op;
        buf.undo_index = (buf.undo_index + 1) % UNDO_BUFFER_SIZE;
    }
}

fn undoOperation(data: [*]u8, buf: *FileBuffer, editor: *Editor) void {
    if (buf.undo_count == 0) return;

    // Move index back
    if (buf.undo_index == 0) buf.undo_index = UNDO_BUFFER_SIZE - 1 else buf.undo_index -= 1;
    const op = buf.undo_buffer[buf.undo_index];
    buf.undo_count -= 1;

    if (op.op_type == .insert) {
        // Undo insert = Delete
        // Shift left from position
        var i: usize = op.position;
        while (i < buf.file_size - 1) {
            data[i] = data[i + 1];
            i += 1;
        }
        // Restore cursor
        const pos = getPositionFromByteOffset(data, buf.file_size, op.position);
        editor.cursor_col = pos.col;
        editor.cursor_row = pos.row;
    } else if (op.op_type == .delete) {
        // Undo delete = Insert
        // Shift right
        var i: usize = buf.file_size; // Assume buffer has space
        // Wait, insert logic used buf.file_size?
        // Yes, assuming buffer capacity > file_size for now.

        while (i > op.position) {
            data[i] = data[i - 1];
            i -= 1;
        }
        data[op.position] = op.char;

        // Move cursor to after inserted char
        const pos = getPositionFromByteOffset(data, buf.file_size, op.position + 1);
        editor.cursor_col = pos.col;
        editor.cursor_row = pos.row;
    }
}

// Navigation Helpers (Ported from legacy/main.zig)

fn moveCursorBuffer(data: [*]const u8, file_size: usize, editor: *Editor, move: CursorMove) void {
    const max_col = getLineLength(data, file_size, editor.cursor_row);

    switch (move) {
        .up => {
            if (editor.cursor_row > 0) {
                editor.cursor_row -= 1;
                editor.cursor_col = @min(editor.cursor_col, getLineLength(data, file_size, editor.cursor_row));
            }
        },
        .down => {
            const total_lines = getTotalLines(data, file_size);
            if (editor.cursor_row < total_lines - 1) {
                editor.cursor_row += 1;
                editor.cursor_col = @min(editor.cursor_col, getLineLength(data, file_size, editor.cursor_row));
            }
        },
        .left => {
            if (editor.cursor_col > 0) {
                editor.cursor_col -= 1;
            }
        },
        .right => {
            if (editor.cursor_col < max_col) {
                editor.cursor_col += 1;
            }
        },
        .home => {
            editor.cursor_col = 0;
        },
        .end => {
            editor.cursor_col = max_col;
        },
        .page_up => {
            if (editor.line_offset >= VIEWPORT_ROWS) {
                editor.line_offset -= VIEWPORT_ROWS;
                if (editor.cursor_row > editor.line_offset + VIEWPORT_ROWS - 1) {
                    editor.cursor_row = editor.line_offset + VIEWPORT_ROWS - 1;
                }
            } else {
                editor.line_offset = 0;
                editor.cursor_row = 0;
            }
        },
        .page_down => {
            const total_lines = getTotalLines(data, file_size);
            const max_offset = if (total_lines > VIEWPORT_ROWS) total_lines - VIEWPORT_ROWS else 0;
            if (editor.line_offset < max_offset) {
                editor.line_offset += VIEWPORT_ROWS;
                if (editor.line_offset > max_offset) {
                    editor.line_offset = max_offset;
                }
                if (editor.cursor_row < editor.line_offset) {
                    editor.cursor_row = editor.line_offset;
                }
            }
        },
        .page_begin => {
            editor.line_offset = 0;
            editor.cursor_row = 0;
            editor.cursor_col = 0;
        },
        .page_end => {
            const total_lines = getTotalLines(data, file_size);
            editor.line_offset = if (total_lines > VIEWPORT_ROWS) total_lines - VIEWPORT_ROWS else 0;
            editor.cursor_row = if (total_lines > 0) total_lines - 1 else 0;
            editor.cursor_col = getLineLength(data, file_size, editor.cursor_row);
        },
        .word_next => {
            var pos = getByteOffset(data, file_size, editor.cursor_row, editor.cursor_col);
            const line_end = findLineEnd(data, file_size, editor.cursor_row);

            while (pos < line_end and !isWordChar(data[pos])) : (pos += 1) {}
            while (pos < line_end and isWordChar(data[pos])) {
                pos += 1;
            }

            const new_pos = getPositionFromByteOffset(data, file_size, pos);
            editor.cursor_row = new_pos.row;
            editor.cursor_col = new_pos.col;
        },
        .word_prev => {
            var pos = getByteOffset(data, file_size, editor.cursor_row, editor.cursor_col);
            if (pos > 0) pos -= 1;

            while (pos > 0 and !isWordChar(data[pos])) : (pos -= 1) {}
            while (pos > 0 and isWordChar(data[pos])) {
                pos -= 1;
            }
            if (pos > 0 and !isWordChar(data[pos])) pos += 1;

            const new_pos = getPositionFromByteOffset(data, file_size, pos);
            editor.cursor_row = new_pos.row;
            editor.cursor_col = new_pos.col;
        },
        .word_end => {
            var pos = getByteOffset(data, file_size, editor.cursor_row, editor.cursor_col);
            const line_end = findLineEnd(data, file_size, editor.cursor_row);

            while (pos < line_end and isWordChar(data[pos])) {
                pos += 1;
            }
            while (pos < line_end and !isWordChar(data[pos])) {
                pos += 1;
            }

            if (pos > 0) pos -= 1;
            const new_pos = getPositionFromByteOffset(data, file_size, pos);
            editor.cursor_row = new_pos.row;
            editor.cursor_col = new_pos.col;
        },
    }
}

fn getLineLength(data: [*]const u8, file_size: usize, line_num: usize) usize {
    var byte_offset: usize = 0;
    var current_line: usize = 0;

    while (current_line < line_num and byte_offset < file_size) {
        while (byte_offset < file_size and data[byte_offset] != '\n') {
            byte_offset += 1;
        }
        if (byte_offset < file_size) {
            byte_offset += 1;
            current_line += 1;
        }
    }

    const line_start = byte_offset;
    while (byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
    }

    return byte_offset - line_start;
}

fn getTotalLines(data: [*]const u8, file_size: usize) usize {
    var count: usize = 0;
    for (0..file_size) |i| {
        if (data[i] == '\n') count += 1;
    }
    return count + 1;
}

fn getByteOffset(data: [*]const u8, file_size: usize, row: usize, col: usize) usize {
    _ = file_size;
    var byte_offset: usize = 0;
    var current_row: usize = 0;

    while (current_row < row) : (current_row += 1) {
        while (data[byte_offset] != '\n') : (byte_offset += 1) {}
        byte_offset += 1;
    }

    return byte_offset + col;
}

fn findLineEnd(data: [*]const u8, file_size: usize, row: usize) usize {
    var byte_offset: usize = 0;
    var current_row: usize = 0;

    while (current_row < row) : (current_row += 1) {
        while (data[byte_offset] != '\n') : (byte_offset += 1) {}
        byte_offset += 1;
    }

    while (byte_offset < file_size and data[byte_offset] != '\n') : (byte_offset += 1) {}
    return byte_offset;
}

fn isWordChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

fn getPositionFromByteOffset(data: [*]const u8, file_size: usize, byte_offset: usize) Position {
    var row: usize = 0;
    var col: usize = 0;
    var i: usize = 0;
    while (i < byte_offset and i < file_size) : (i += 1) {
        if (data[i] == '\n') {
            row += 1;
            col = 0;
        } else {
            col += 1;
        }
    }
    return Position{ .row = row, .col = col };
}
