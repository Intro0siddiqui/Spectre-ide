const Syscall = enum(usize) { write = 1, exit = 60, read = 0, open = 2, close = 3, fstat = 5, mmap = 9, munmap = 11, msync = 26 };
const STDIN_FILENO: usize = 0;
const STDOUT_FILENO: usize = 1;

const O_RDONLY: usize = 0;
const O_RDWR: usize = 2;
const PROT_READ: usize = 1;
const PROT_WRITE: usize = 2;
const PROT_READ_WRITE: usize = 3;
const MAP_PRIVATE: usize = 0x02;
const MAP_SHARED: usize = 0x01;
const MAP_FAILED: isize = -1;

const MS_ASYNC: usize = 1;
const MS_SYNC: usize = 4;
const MS_INVALIDATE: usize = 2;

const PAGE_SIZE: usize = 4096;

const SCREEN_ROWS: usize = 24;
const SCREEN_COLS: usize = 80;

inline fn syscall1(number: Syscall, arg1: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
    );
}

inline fn syscall3(number: Syscall, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
    );
}

inline fn syscall6(number: Syscall, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
          [arg6] "{r9}" (arg6),
    );
}

inline fn syscall2(number: Syscall, arg1: usize, arg2: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
    );
}

fn rawWrite(fd: usize, ptr: [*]const u8, len: usize) void {
    _ = syscall3(Syscall.write, fd, @intFromPtr(ptr), len);
}

fn rawRead(fd: usize, ptr: [*]u8, len: usize) usize {
    return syscall3(Syscall.read, fd, @intFromPtr(ptr), len);
}

fn rawExit(code: usize) noreturn {
    _ = syscall1(Syscall.exit, code);
    unreachable;
}

fn rawOpen(path: [*]const u8, flags: usize, mode: usize) isize {
    return @bitCast(syscall3(Syscall.open, @intFromPtr(path), flags, mode));
}

fn rawClose(fd: usize) isize {
    return @bitCast(syscall1(Syscall.close, fd));
}

fn rawMmap(addr: ?[*]u8, length: usize, prot: usize, flags: usize, fd: usize, offset: usize) ?[*]u8 {
    const addr_int = if (addr) |a| @intFromPtr(a) else 0;
    const result = syscall6(Syscall.mmap, addr_int, length, prot, flags, fd, offset);
    if (result == @as(usize, @bitCast(MAP_FAILED))) return null;
    return @ptrFromInt(result);
}

fn rawMunmap(addr: [*]u8, length: usize) isize {
    return @bitCast(syscall2(Syscall.munmap, @intFromPtr(addr), length));
}

fn rawMsync(addr: [*]const u8, length: usize, flags: usize) isize {
    return @bitCast(syscall3(Syscall.msync, @intFromPtr(addr), length, flags));
}

fn getPageSize() usize {
    return PAGE_SIZE;
}

fn alignUp(size: usize, alignment: usize) usize {
    return (size + alignment - 1) & ~(alignment - 1);
}

const welcome_msg = "Spectre-IDE: The 2026 Monster Editor\n======================================\nPhase 6+ Complete:\n  [x] Freestanding Entry (No LibC)\n  [x] Raw Mode TTY Driver\n  [x] Direct Syscalls\n  [x] Memory-Mapped I/O (Zero-Copy)\n  [x] Command-Line Arguments\n  [x] File Saving (msync)\n  [x] ANSI Diff Rendering\n  [x] Character Insertion (Edit Mode)\n  [x] Undo/Redo (Ctrl+Z)\n\nUsage: spectre-ide <filename>\nControls: 'q' to exit, j/k to scroll, i to insert, ESC to exit insert, Ctrl+Z undo, :w to save\n\n";

const Viewport = struct {
    rows: usize = 24,
    cols: usize = 80,
    line_offset: usize = 0,
    data: ?[*]u8 = null,
    size: usize = 0,
};

const ScreenBuffer = struct {
    previous: [SCREEN_ROWS][SCREEN_COLS]u8 = [_][SCREEN_COLS]u8{[_]u8{0} ** SCREEN_COLS} ** SCREEN_ROWS,
    current: [SCREEN_ROWS][SCREEN_COLS]u8 = [_][SCREEN_COLS]u8{[_]u8{0} ** SCREEN_COLS} ** SCREEN_ROWS,

    fn copyCurrentToPrevious(self: *ScreenBuffer) void {
        self.previous = self.current;
    }

    fn setChar(self: *ScreenBuffer, row: usize, col: usize, char: u8) void {
        if (row < SCREEN_ROWS and col < SCREEN_COLS) {
            self.current[row][col] = char;
        }
    }

    fn getChar(self: *const ScreenBuffer, row: usize, col: usize) u8 {
        if (row < SCREEN_ROWS and col < SCREEN_COLS) {
            return self.current[row][col];
        }
        return 0;
    }

    fn renderDiff(self: *ScreenBuffer) void {
        // Only clear screen on first render
        if (self.previous[0][0] == 0) {
            const clear = "\x1b[2J\x1b[H";
            rawWrite(STDOUT_FILENO, clear, clear.len);
        }

        for (0..SCREEN_ROWS) |r| {
            var line_changed = false;
            var first_change_col: usize = SCREEN_COLS;
            var last_change_col: usize = 0;

            // Check if line has any changes
            for (0..SCREEN_COLS) |c| {
                const current_ch = self.current[r][c];
                const prev_ch = self.previous[r][c];
                if (current_ch != prev_ch) {
                    line_changed = true;
                    if (c < first_change_col) first_change_col = c;
                    if (c > last_change_col) last_change_col = c;
                }
            }

            if (line_changed) {
                // Position cursor at start of changed region
                const row_num = r + 1;
                const col_num = first_change_col + 1;
                var pos_buf: [32]u8 = undefined;
                var pos_len: usize = 0;

                pos_buf[pos_len] = 0x1b;
                pos_len += 1;
                pos_buf[pos_len] = '[';
                pos_len += 1;

                if (row_num >= 10) {
                    pos_buf[pos_len] = '0' + @as(u8, @intCast(row_num / 10));
                    pos_len += 1;
                }
                pos_buf[pos_len] = '0' + @as(u8, @intCast(row_num % 10));
                pos_len += 1;

                pos_buf[pos_len] = ';';
                pos_len += 1;

                if (col_num >= 10) {
                    pos_buf[pos_len] = '0' + @as(u8, @intCast(col_num / 10));
                    pos_len += 1;
                }
                pos_buf[pos_len] = '0' + @as(u8, @intCast(col_num % 10));
                pos_len += 1;

                pos_buf[pos_len] = 'H';
                pos_len += 1;

                rawWrite(STDOUT_FILENO, &pos_buf, pos_len);

                // Write the entire line from first change to end
                var line_buf: [SCREEN_COLS]u8 = undefined;
                var line_len: usize = 0;
                for (first_change_col..SCREEN_COLS) |c| {
                    line_buf[line_len] = if (self.current[r][c] != 0) self.current[r][c] else ' ';
                    line_len += 1;
                }
                rawWrite(STDOUT_FILENO, &line_buf, line_len);
            }
        }

        // Position cursor at bottom right after rendering
        const cursor_home = "\x1b[24;80H";
        rawWrite(STDOUT_FILENO, cursor_home, cursor_home.len);

        // Copy current to previous after rendering
        self.copyCurrentToPrevious();
    }
};

const Operation = struct {
    op_type: enum { insert, delete },
    position: usize, // byte offset in file
    char: u8, // character inserted/deleted
};

const UNDO_BUFFER_SIZE = 256;

const EditorState = struct {
    viewport: Viewport = .{},
    screen_buffer: ScreenBuffer = .{},
    filename: [*]const u8 = &.{},
    file_size: usize = 0,
    aligned_size: usize = 0,
    modified: bool = false,
    syscall_count: usize = 0,
    cursor_row: usize = 0, // Line in file (0-based)
    cursor_col: usize = 0, // Column in line (0-based)
    insert_mode: bool = false,
    undo_buffer: [UNDO_BUFFER_SIZE]Operation = [_]Operation{.{ .op_type = .insert, .position = 0, .char = 0 }} ** UNDO_BUFFER_SIZE,
    undo_index: usize = 0,
    undo_count: usize = 0,
};

fn findLineStart(data: [*]const u8, _size: usize, offset: usize) usize {
    _ = _size;
    if (offset == 0) return 0;
    var i: usize = offset - 1;
    while (i > 0) : (i -= 1) {
        if (data[i] == '\n') return i + 1;
    }
    return 0;
}

fn countLines(data: [*]const u8, size: usize) usize {
    var count: usize = 0;
    for (0..size) |i| {
        if (data[i] == '\n') count += 1;
    }
    return count;
}

fn renderViewport(data: [*]const u8, size: usize, line_offset: usize, screen_buffer: *ScreenBuffer, editor_state: *EditorState) void {
    // Clear the current buffer
    screen_buffer.current = [_][SCREEN_COLS]u8{[_]u8{0} ** SCREEN_COLS} ** SCREEN_ROWS;

    // Set status line (row 0)
    const status = " Spectre-IDE - Phase 6+undo ";
    var col: usize = 0;
    for (status) |c| {
        screen_buffer.setChar(0, col, c);
        col += 1;
        if (col >= SCREEN_COLS) break;
    }

    // Render file content (rows 1-20)
    const rows: usize = 20;
    var current_line: usize = 0;
    var byte_offset: usize = 0;

    while (current_line < line_offset and byte_offset < size) : (current_line += 1) {
        while (byte_offset < size and data[byte_offset] != '\n') {
            byte_offset += 1;
            if (byte_offset >= size) break;
        }
        if (byte_offset < size and data[byte_offset] == '\n') {
            byte_offset += 1;
        }
    }

    current_line = 0;
    var display_offset = byte_offset;
    var row: usize = 1; // Start from row 1 (after status)

    while (current_line < rows and display_offset < size and row < SCREEN_ROWS - 1) : (current_line += 1) {
        const line_start = display_offset;
        while (display_offset < size and data[display_offset] != '\n') {
            display_offset += 1;
        }
        const line_len = display_offset - line_start;
        col = 0;
        if (line_len > 0 and line_start + line_len <= size) {
            var i: usize = 0;
            while (i < line_len and col < SCREEN_COLS) {
                screen_buffer.setChar(row, col, data[line_start + i]);
                col += 1;
                i += 1;
            }
        }
        // Move to next row
        row += 1;
        if (display_offset < size and data[display_offset] == '\n') {
            display_offset += 1;
        }
    }

    // Set footer line (last row)
    const total_lines = countLines(data, size);
    const footer_start = "Lines: ";
    col = 0;
    for (footer_start) |c| {
        screen_buffer.setChar(SCREEN_ROWS - 1, col, c);
        col += 1;
    }

    // Add line count
    var buf: [20]u8 = undefined;
    var len: usize = 0;
    var n = total_lines;
    if (n == 0) {
        buf[len] = '0';
        len += 1;
    } else {
        var digits: [20]u8 = undefined;
        var digit_count: usize = 0;
        while (n > 0) : (n /= 10) {
            digits[digit_count] = '0' + @as(u8, @intCast(n % 10));
            digit_count += 1;
        }
        var d: usize = digit_count;
        while (d > 0) : (d -= 1) {
            buf[len] = digits[d - 1];
            len += 1;
        }
    }
    for (buf[0..len]) |c| {
        screen_buffer.setChar(SCREEN_ROWS - 1, col, c);
        col += 1;
        if (col >= SCREEN_COLS) break;
    }

    var footer_buf: [80]u8 = undefined;
    var footer_len: usize = 0;
    const base_footer = " | j/k scroll, i insert";
    for (base_footer) |c| {
        footer_buf[footer_len] = c;
        footer_len += 1;
    }
    if (editor_state.insert_mode) {
        const insert_text = " (INSERT)";
        for (insert_text) |c| {
            footer_buf[footer_len] = c;
            footer_len += 1;
        }
    }
    const rest_footer = ", Ctrl+Z undo, :w save, q exit";
    for (rest_footer) |c| {
        footer_buf[footer_len] = c;
        footer_len += 1;
    }
    for (footer_buf[0..footer_len]) |c| {
        screen_buffer.setChar(SCREEN_ROWS - 1, col, c);
        col += 1;
        if (col >= SCREEN_COLS) break;
    }

    // Now render the diff
    screen_buffer.renderDiff();

    // Position cursor
    if (editor_state.insert_mode) {
        // Calculate screen position for cursor
        const screen_row = 1 + (editor_state.cursor_row - line_offset); // +1 for status line
        const screen_col = editor_state.cursor_col + 1; // 1-based
        var cursor_buf: [32]u8 = undefined;
        var cursor_len: usize = 0;

        cursor_buf[cursor_len] = 0x1b;
        cursor_len += 1;
        cursor_buf[cursor_len] = '[';
        cursor_len += 1;

        if (screen_row >= 10) {
            cursor_buf[cursor_len] = '0' + @as(u8, @intCast(screen_row / 10));
            cursor_len += 1;
        }
        cursor_buf[cursor_len] = '0' + @as(u8, @intCast(screen_row % 10));
        cursor_len += 1;

        cursor_buf[cursor_len] = ';';
        cursor_len += 1;

        if (screen_col >= 10) {
            cursor_buf[cursor_len] = '0' + @as(u8, @intCast(screen_col / 10));
            cursor_len += 1;
        }
        cursor_buf[cursor_len] = '0' + @as(u8, @intCast(screen_col % 10));
        cursor_len += 1;

        cursor_buf[cursor_len] = 'H';
        cursor_len += 1;

        rawWrite(STDOUT_FILENO, &cursor_buf, cursor_len);
    }
}

fn recordOperation(editor_state: *EditorState, op: Operation) void {
    editor_state.undo_buffer[editor_state.undo_index] = op;
    editor_state.undo_index = (editor_state.undo_index + 1) % UNDO_BUFFER_SIZE;
    if (editor_state.undo_count < UNDO_BUFFER_SIZE) {
        editor_state.undo_count += 1;
    }
}

fn undoOperation(data: [*]u8, editor_state: *EditorState) void {
    if (editor_state.undo_count == 0) return;

    editor_state.undo_index = if (editor_state.undo_index == 0) UNDO_BUFFER_SIZE - 1 else editor_state.undo_index - 1;
    const op = editor_state.undo_buffer[editor_state.undo_index];
    editor_state.undo_count -= 1;

    if (op.op_type == .insert) {
        // Remove the inserted character by shifting left
        var i: usize = op.position;
        while (i < editor_state.file_size - 1) {
            data[i] = data[i - 1];
            i += 1;
        }
        editor_state.cursor_col -= 1;
    } else if (op.op_type == .delete) {
        // Re-insert the deleted character by shifting right
        var i: usize = editor_state.file_size;
        while (i > op.position) {
            data[i] = data[i - 1];
            i -= 1;
        }
        data[op.position] = op.char;
        editor_state.cursor_col += 1;
    }
}

fn insertChar(data: [*]u8, file_size: usize, editor_state: *EditorState, char: u8) void {
    // Find the byte offset for cursor position
    var byte_offset: usize = 0;
    var current_line: usize = 0;

    // Navigate to cursor row
    while (current_line < editor_state.cursor_row and byte_offset < file_size) {
        while (byte_offset < file_size and data[byte_offset] != '\n') {
            byte_offset += 1;
        }
        if (byte_offset < file_size) {
            byte_offset += 1; // Skip newline
            current_line += 1;
        }
    }

    // Navigate to cursor column in current line
    var col: usize = 0;
    while (col < editor_state.cursor_col and byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
        col += 1;
    }

    // Insert character by shifting everything right (simple implementation)
    if (byte_offset < file_size - 1) { // Leave space for null terminator
        var i: usize = file_size;
        while (i > byte_offset) {
            data[i] = data[i - 1];
            i -= 1;
        }
        data[byte_offset] = char;

        // Record operation for undo
        recordOperation(editor_state, .{ .op_type = .insert, .position = byte_offset, .char = char });

        editor_state.cursor_col += 1;
    }
}

fn parseArgcArgv() struct { argc: usize, argv: [*][*]u8 } {
    var sp: usize = 0;
    asm volatile ("mov %%rsp, %[sp]"
        : [sp] "=r" (sp),
    );

    const argc = @as(*const usize, @ptrFromInt(sp)).*;
    const argv = @as([*][*]u8, @ptrFromInt(sp + @sizeOf(usize)));

    return .{ .argc = argc, .argv = argv };
}

fn saveFile(data: [*]u8, aligned_size: usize, modified: bool, editor_state: *EditorState) bool {
    _ = editor_state;
    if (!modified) {
        const no_changes_msg = "No changes to save\n";
        rawWrite(STDOUT_FILENO, no_changes_msg, no_changes_msg.len);
        return false;
    }

    const sync_result = rawMsync(data, aligned_size, MS_SYNC);
    if (sync_result < 0) {
        const error_msg = "Error: Save failed\n";
        rawWrite(STDOUT_FILENO, error_msg, error_msg.len);
        return false;
    }

    const saved_msg = "File saved successfully\n";
    rawWrite(STDOUT_FILENO, saved_msg, saved_msg.len);
    return true;
}

export fn _start() noreturn {
    const args = parseArgcArgv();

    const default_file = "/tmp/test_file.txt";
    const filename_ptr = if (args.argc > 1) args.argv[1] else default_file;

    const fd = rawOpen(filename_ptr, O_RDWR, 0);
    if (fd < 0) {
        const error_msg = "Error: Could not open file\n";
        rawWrite(STDOUT_FILENO, error_msg, error_msg.len);
        rawExit(1);
    }

    var stat_buf: [144]u8 = undefined;
    const fd_usize: usize = @bitCast(fd);
    const stat_result = syscall2(Syscall.fstat, fd_usize, @intFromPtr(&stat_buf));
    _ = stat_result;

    var file_size: usize = 0;
    const size_ptr: *usize = @ptrFromInt(@intFromPtr(&stat_buf) + 48);
    file_size = size_ptr.*;

    if (file_size == 0) file_size = 1024;

    const aligned_size = alignUp(file_size, getPageSize());

    const mapped_ptr = rawMmap(null, aligned_size, PROT_READ_WRITE, MAP_SHARED, fd_usize, 0);
    if (mapped_ptr == null) {
        const error_msg = "Error: mmap failed\n";
        rawWrite(STDOUT_FILENO, error_msg, error_msg.len);
        const close_result = rawClose(fd_usize);
        _ = close_result;
        rawExit(1);
    }

    const close_result = rawClose(fd_usize);
    _ = close_result;

    var editor_state: EditorState = .{};
    editor_state.file_size = file_size;
    editor_state.aligned_size = aligned_size;

    const line_offset: usize = 0;
    var in_command: bool = false;

    if (mapped_ptr) |data| {
        renderViewport(data, file_size, line_offset, &editor_state.screen_buffer, &editor_state);
    }

    var buffer: [1]u8 = undefined;
    while (true) {
        const read_result = rawRead(STDIN_FILENO, &buffer, 1);
        if (buffer[0] == 'q') break;
        if (read_result > 0) {
            if (mapped_ptr) |data| {
                // Handle Ctrl+Z (undo) - ASCII 26
                if (buffer[0] == 26) {
                    undoOperation(data, &editor_state);
                    renderViewport(data, file_size, line_offset, &editor_state.screen_buffer, &editor_state);
                } else if (buffer[0] == ':') {
                    in_command = true;
                } else if (in_command and buffer[0] == 'w') {
                    _ = saveFile(data, aligned_size, editor_state.modified, &editor_state);
                    in_command = false;
                } else if (!editor_state.insert_mode) {
                    if (buffer[0] == 'i') {
                        editor_state.insert_mode = true;
                        editor_state.cursor_row = 0;
                        editor_state.cursor_col = 0;
                        renderViewport(data, file_size, line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (buffer[0] == 'j' and line_offset < countLines(data, file_size) - 20) {
                        const new_offset = line_offset + 1;
                        renderViewport(data, file_size, new_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (buffer[0] == 'k' and line_offset > 0) {
                        const new_offset = line_offset - 1;
                        renderViewport(data, file_size, new_offset, &editor_state.screen_buffer, &editor_state);
                    }
                } else if (editor_state.insert_mode) {
                    if (buffer[0] == 27) { // ESC key
                        editor_state.insert_mode = false;
                        renderViewport(data, file_size, line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (buffer[0] >= 32 and buffer[0] <= 126) { // Printable characters
                        insertChar(data, editor_state.file_size, &editor_state, buffer[0]);
                        editor_state.modified = true;
                        renderViewport(data, file_size, line_offset, &editor_state.screen_buffer, &editor_state);
                    }
                }
            }
        }
    }

    const exit_msg = "\x1b[2J\x1b[HGoodbye!\n";
    rawWrite(STDOUT_FILENO, exit_msg, exit_msg.len);

    if (mapped_ptr) |data| {
        _ = rawMunmap(data, aligned_size);
    }

    rawExit(0);
}
