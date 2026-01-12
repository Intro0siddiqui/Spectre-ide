const Syscall = enum(usize) { write = 1, exit = 60, read = 0, open = 2, close = 3, fstat = 5, mmap = 9, munmap = 11, msync = 26, mremap = 25, ftruncate = 77 };
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

const ANSI_COLOR_DEFAULT = 0;
const ANSI_COLOR_KEYWORD = 33;
const ANSI_COLOR_STRING = 32;
const ANSI_COLOR_NUMBER = 36;
const ANSI_COLOR_COMMENT = 90;
const ANSI_COLOR_FUNCTION = 34;
const ANSI_COLOR_TYPE = 35;
const ANSI_COLOR_VARIABLE = 31;
const ANSI_COLOR_ERROR = 31;
const ANSI_COLOR_WARNING = 33;
const ANSI_COLOR_CLASS = 35;
const ANSI_COLOR_PARAMETER = 37;
const ANSI_COLOR_PROPERTY = 37;

const ansi_mouse = @import("ansi_mouse.zig");
const mouse = @import("mouse.zig");

const LSPClient = @import("lsp_client.zig").LSPClient;
const Config = @import("config.zig").Config;
const getLspServer = @import("lsp_client.zig").getLspServer;
const getLspServerByName = @import("lsp_client.zig").getLspServerByName;
const makeFileUri = @import("lsp_client.zig").makeFileUri;
const SemanticToken = @import("lsp_client.zig").SemanticToken;
const SemanticTokens = @import("lsp_client.zig").SemanticTokens;
const Diagnostic = @import("lsp_client.zig").Diagnostic;
const Diagnostics = @import("lsp_client.zig").Diagnostics;

fn detectLanguageId(filename: [*]const u8) []const u8 {
    var i: usize = 0;
    while (filename[i] != 0) : (i += 1) {}
    const len = i;

    var ext_start: usize = len;
    while (ext_start > 0 and filename[ext_start - 1] != '.') : (ext_start -= 1) {}

    if (ext_start == 0 or ext_start == len) return "plaintext";

    const ext_len = len - ext_start;
    if (ext_len < 2 or ext_len > 4) return "plaintext";

    if (ext_len == 3) {
        const e1 = filename[ext_start];
        const e2 = filename[ext_start + 1];
        const e3 = filename[ext_start + 2];

        if ((e1 == 'z' or e1 == 'Z') and (e2 == 'i' or e2 == 'I') and (e3 == 'g' or e3 == 'G')) return "zig";
        if ((e1 == 'p' or e1 == 'P') and (e2 == 'y' or e2 == 'Y')) return "python";
        if ((e1 == 'r' or e1 == 'R') and (e2 == 's' or e2 == 'S')) return "rust";
        if ((e1 == 'g' or e1 == 'G') and (e2 == 'o' or e2 == 'O')) return "go";
        if ((e1 == 'j' or e1 == 'J') and (e2 == 's' or e2 == 'S')) return "javascript";
        if ((e1 == 'j' or e1 == 'J') and (e2 == 'a' or e2 == 'A')) return "java";
        if ((e1 == 's' or e1 == 'S') and (e2 == 'h' or e2 == 'H')) return "shell";
        if ((e1 == 'm' or e1 == 'M') and (e2 == 'd' or e2 == 'D')) return "markdown";
    }

    if (ext_len == 2) {
        const e1 = filename[ext_start];
        const e2 = filename[ext_start + 1];
        if ((e1 == 'c' or e1 == 'C') and (e2 == 'c' or e2 == 'C')) return "cpp";
        if ((e1 == 'c' or e1 == 'C') and (e2 == 'h' or e2 == 'H')) return "c";
    }

    return "plaintext";
}

// LSP Client structures
const SyntaxHighlight = struct {
    row: usize,
    start_col: usize,
    end_col: usize,
    color: u8,
    bold: bool = false,
};

const MAX_HIGHLIGHTS = 4096;

const SyntaxHighlighter = struct {
    highlights: [MAX_HIGHLIGHTS]SyntaxHighlight = undefined,
    count: usize = 0,

    fn reset(self: *SyntaxHighlighter) void {
        self.count = 0;
    }

    fn addHighlight(self: *SyntaxHighlighter, row: usize, start_col: usize, end_col: usize, color: u8, bold: bool) void {
        if (self.count < MAX_HIGHLIGHTS) {
            self.highlights[self.count] = .{ .row = row, .start_col = start_col, .end_col = end_col, .color = color, .bold = bold };
            self.count += 1;
        }
    }

    fn getHighlightAt(self: *const SyntaxHighlighter, row: usize, col: usize) ?u8 {
        for (0..self.count) |i| {
            const h = self.highlights[i];
            if (h.row == row and col >= h.start_col and col < h.end_col) {
                return h.color;
            }
        }
        return null;
    }
};

fn fileExtension(filename: [*]const u8) []const u8 {
    var i: usize = 0;
    while (filename[i] != 0) : (i += 1) {}
    const len = i;

    i = len;
    while (i > 0 and filename[i - 1] != '.') : (i -= 1) {}
    if (i > 0 and i < len) {
        return filename[i..len];
    }
    return "";
}

fn detectLanguage(ext: []const u8) []const u8 {
    if (ext.len < 2) return "plaintext";

    if (memeqString(ext, "zig")) return "zig";
    if (memeqString(ext, "c") or memeqString(ext, "h")) return "c";
    if (memeqString(ext, "cpp") or memeqString(ext, "cxx") or memeqString(ext, "hpp")) return "cpp";
    if (memeqString(ext, "py")) return "python";
    if (memeqString(ext, "js") or memeqString(ext, "ts")) return "javascript";
    if (memeqString(ext, "rs")) return "rust";
    if (memeqString(ext, "go")) return "go";
    if (memeqString(ext, "java")) return "java";
    if (memeqString(ext, "json")) return "json";
    if (memeqString(ext, "sh") or memeqString(ext, "bash") or memeqString(ext, "zsh")) return "shell";
    if (memeqString(ext, "md") or memeqString(ext, "txt")) return "markdown";

    return "plaintext";
}

fn memeqString(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        const ax = if (x >= 'A' and x <= 'Z') x + 32 else x;
        const by = if (y >= 'A' and y <= 'Z') y + 32 else y;
        if (ax != by) return false;
    }
    return true;
}

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

inline fn syscall5(number: Syscall, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
    );
}

inline fn syscall0(number: Syscall) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
    );
}

inline fn syscall4(number: Syscall, arg1: usize, arg2: usize, arg3: usize, arg4: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
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

fn rawMremap(old_addr: [*]u8, old_size: usize, new_size: usize, flags: usize) ?[*]u8 {
    const result = syscall5(Syscall.mremap, @intFromPtr(old_addr), old_size, new_size, flags, 0);
    if (result == @as(usize, @bitCast(@as(isize, -1)))) return null;
    return @ptrFromInt(result);
}

fn rawFtruncate(fd: usize, length: usize) isize {
    return @bitCast(syscall2(Syscall.ftruncate, fd, length));
}

fn rawFork() isize {
    return @bitCast(syscall0(Syscall.fork));
}

fn rawExecve(path: [*]const u8, argv: [*][*]u8, envp: [*][*]u8) isize {
    return @bitCast(syscall3(Syscall.execve, @intFromPtr(path), @intFromPtr(argv), @intFromPtr(envp)));
}

fn rawPipe(pipefd: [*]usize) isize {
    return @bitCast(syscall1(Syscall.pipe, @intFromPtr(pipefd)));
}

fn rawDup2(oldfd: usize, newfd: usize) isize {
    return @bitCast(syscall2(Syscall.dup2, oldfd, newfd));
}

fn rawWaitpid(pid: usize, wstatus: [*]usize, options: usize) isize {
    return @bitCast(syscall4(Syscall.waitpid, pid, @intFromPtr(wstatus), options, 0));
}

fn getPageSize() usize {
    return PAGE_SIZE;
}

fn alignUp(size: usize, alignment: usize) usize {
    return (size + alignment - 1) & ~(alignment - 1);
}

const welcome_msg = "Spectre-IDE: The 2026 Monster Editor\n======================================\nPhase 16 Navigation & Config:\n  [x] Freestanding Entry (No LibC)\n  [x] Raw Mode TTY Driver\n  [x] Direct Syscalls\n  [x] Memory-Mapped I/O (Zero-Copy)\n  [x] Command-Line Arguments\n  [x] File Saving (msync)\n  [x] ANSI Diff Rendering\n  [x] Character Insertion (Edit Mode)\n  [x] Undo/Redo (Ctrl+Z)\n  [x] Delete/Backspace Support\n  [x] Cursor Movement\n  [x] Line Operations (Enter, dd, J)\n  [x] Search Functionality (/pattern)\n  [x] Status Bar Enhancements\n  [x] LSP Client Manual Mode\n  [x] Navigation: Page Up/Down, gg/G, w/b/e\n\nLSP Servers: zls, clangd, pylsp, rust-analyzer, gopls, none\nUsage: spectre-ide <filename>\nControls: / search, n next, N prev, h/j/k/l/arrows move, i insert, Enter split, dd delete, J join, ESC exit, BS/Del, Ctrl+Z undo, :w save, :lsp <server> enable LSP, :<num> goto line, PgUp/PgDn, gg/G, w/b/e, q quit\n\n";

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

const SEARCH_BUFFER_SIZE = 256;

const EditorState = struct {
    viewport: Viewport = .{},
    screen_buffer: ScreenBuffer = .{},
    filename: [*]const u8 = &.{},
    file_size: usize = 0,
    aligned_size: usize = 0,
    modified: bool = false,
    syscall_count: usize = 0,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    insert_mode: bool = false,
    line_offset: usize = 0,
    undo_buffer: [UNDO_BUFFER_SIZE]Operation = [_]Operation{.{ .op_type = .insert, .position = 0, .char = 0 }} ** UNDO_BUFFER_SIZE,
    undo_index: usize = 0,
    undo_count: usize = 0,
    search_mode: bool = false,
    search_buffer: [SEARCH_BUFFER_SIZE]u8 = [_]u8{0} ** SEARCH_BUFFER_SIZE,
    search_len: usize = 0,
    search_match_row: usize = 0,
    search_match_col: usize = 0,
    search_match_offset: usize = 0,
    lsp_client: LSPClient = undefined,
    semantic_tokens: SemanticTokens = undefined,
    diagnostics: Diagnostics = undefined,
    lsp_active: bool = false,
    lsp_uri: [256]u8 = undefined,
    file_version: usize = 1,
    lsp_server_name: [32]u8 = undefined,
    command_buffer: [64]u8 = undefined,
    command_len: usize = 0,
    buffer_index: usize = 0,
    buffer_count: usize = 1,
    config: Config = .{},
};

const MAX_BUFFERS = 16;

const FileBuffer = struct {
    filename: [256]u8 = undefined,
    filename_len: usize = 0,
    data: ?[*]u8 = null,
    file_size: usize = 0,
    aligned_size: usize = 0,
    modified: bool = false,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    line_offset: usize = 0,
    undo_buffer: [UNDO_BUFFER_SIZE]Operation = [_]Operation{.{ .op_type = .insert, .position = 0, .char = 0 }} ** UNDO_BUFFER_SIZE,
    undo_index: usize = 0,
    undo_count: usize = 0,
    lsp_client: LSPClient = undefined,
    lsp_active: bool = false,
    lsp_uri: [256]u8 = undefined,
    file_version: usize = 1,
    lsp_server_name: [32]u8 = undefined,
};

const BufferManager = struct {
    buffers: [MAX_BUFFERS]FileBuffer = undefined,
    count: usize = 0,
    current: usize = 0,

    fn init() BufferManager {
        var bm: BufferManager = undefined;
        bm.count = 0;
        bm.current = 0;
        return bm;
    }

    fn addFile(self: *BufferManager, filename: [*]const u8, data: ?[*]u8, file_size: usize, aligned_size: usize) ?*FileBuffer {
        if (self.count >= MAX_BUFFERS) return null;

        const buf = &self.buffers[self.count];
        buf.* = FileBuffer{};

        const name_len = nullTerminatedLength(filename);
        if (name_len < 256) {
            @memcpy(buf.filename[0..name_len], filename[0..name_len]);
            buf.filename[name_len] = 0;
            buf.filename_len = name_len;
        }

        buf.data = data;
        buf.file_size = file_size;
        buf.aligned_size = aligned_size;

        self.count += 1;
        self.current = self.count - 1;
        return buf;
    }

    fn getCurrent(self: *BufferManager) *FileBuffer {
        return &self.buffers[self.current];
    }

    fn switchTo(self: *BufferManager, index: usize) bool {
        if (index < self.count) {
            self.current = index;
            return true;
        }
        return false;
    }

    fn next(self: *BufferManager) void {
        if (self.count > 1) {
            self.current = (self.current + 1) % self.count;
        }
    }

    fn previous(self: *BufferManager) void {
        if (self.count > 1) {
            if (self.current == 0) {
                self.current = self.count - 1;
            } else {
                self.current -= 1;
            }
        }
    }

    fn closeCurrent(self: *BufferManager) void {
        if (self.count > 0) {
            const buf = &self.buffers[self.current];
            if (buf.lsp_active) {
                _ = buf.lsp_client.sendShutdown();
                _ = buf.lsp_client.sendExit();
                buf.lsp_client.stopServer();
            }
            if (buf.data) |data| {
                _ = rawMunmap(data, buf.aligned_size);
            }

            var i = self.current;
            while (i < self.count - 1) : (i += 1) {
                self.buffers[i] = self.buffers[i + 1];
            }

            self.count -= 1;
            if (self.current >= self.count and self.count > 0) {
                self.current = self.count - 1;
            }
        }
    }

    fn getBufferList(self: *BufferManager, buf: []u8) usize {
        var pos: usize = 0;
        var i: usize = 0;
        while (i < self.count and pos < buf.len - 1) : (i += 1) {
            const name = self.buffers[i].filename[0..self.buffers[i].filename_len];
            if (self.current == i) {
                buf[pos] = '*';
                pos += 1;
            }
            var j: usize = 0;
            while (j < name.len and pos < buf.len - 1) : (j += 1) {
                buf[pos] = name[j];
                pos += 1;
            }
            if (pos < buf.len - 1) {
                buf[pos] = '\n';
                pos += 1;
            }
        }
        return pos;
    }
};

fn loadFileIntoBuffer(manager: *BufferManager, filename: [*]const u8) bool {
    const fd = rawOpen(filename, O_RDWR, 0);
    if (fd < 0) {
        return false;
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
    _ = rawClose(fd_usize);

    if (mapped_ptr == null) {
        return false;
    }

    _ = manager.addFile(filename, mapped_ptr, file_size, aligned_size);
    return true;
}

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

fn nullTerminatedLength(str: [*]const u8) usize {
    var len: usize = 0;
    while (str[len] != 0) : (len += 1) {}
    return len;
}

fn eqStr(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |char, i| {
        const a_lower = if (char >= 'A' and char <= 'Z') char + 32 else char;
        const b_lower = if (b[i] >= 'A' and b[i] <= 'Z') b[i] + 32 else b[i];
        if (a_lower != b_lower) return false;
    }
    return true;
}

fn parseNumber(s: []const u8) usize {
    var result: usize = 0;
    for (s) |c| {
        if (c >= '0' and c <= '9') {
            result = result * 10 + @as(usize, @intCast(c - '0'));
        }
    }
    return result;
}

fn containsString(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (0..haystack.len - needle.len + 1) |i| {
        var match = true;
        for (0..needle.len) |j| {
            if (haystack[i + j] != needle[j]) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

fn findArrayStart(haystack: []const u8, prefix: []const u8) ?usize {
    if (prefix.len > haystack.len) return null;
    for (0..haystack.len - prefix.len + 1) |i| {
        var match = true;
        for (0..prefix.len) |j| {
            if (haystack[i + j] != prefix[j]) {
                match = false;
                break;
            }
        }
        if (match) {
            var pos = i + prefix.len;
            while (pos < haystack.len and haystack[pos] == ' ') : (pos += 1) {}
            if (pos < haystack.len and haystack[pos] == '[') {
                return pos + 1;
            }
        }
    }
    return null;
}

fn parseUint32Array(arr_str: []const u8, buf: []u32) usize {
    var count: usize = 0;
    var i: usize = 0;
    var current: usize = 0;
    var in_number = false;
    var negative = false;

    while (i < arr_str.len and count < buf.len) : (i += 1) {
        const c = arr_str[i];
        if (c == '-') {
            negative = true;
        } else if (c >= '0' and c <= '9') {
            current = current * 10 + @as(usize, @intCast(c - '0'));
            in_number = true;
        } else if (in_number) {
            if (negative) current = 0 - current;
            buf[count] = @as(u32, @intCast(current));
            count += 1;
            current = 0;
            in_number = false;
            negative = false;
            if (c == ']') break;
        } else if (c == ']') {
            break;
        }
    }
    return count;
}

fn parseDiagnostics(json: []const u8, diagnostics: *Diagnostics) void {
    diagnostics.clear();
    if (!containsString(json, "\"diagnostics\":")) return;

    const arr_start = findArrayStart(json, "\"diagnostics\":[");
    if (arr_start == null) return;

    var i = arr_start.?;
    var brace_depth: usize = 0;
    var in_diag = false;
    var current_diag: usize = 0;

    var diag_ranges: [64]struct { start: usize, end: usize } = undefined;
    var diag_ranges_count: usize = 0;

    while (i < json.len and diag_ranges_count < diag_ranges.len) : (i += 1) {
        if (json[i] == '{') {
            if (brace_depth == 0) {
                current_diag = i;
                in_diag = true;
            }
            brace_depth += 1;
        } else if (json[i] == '}') {
            if (brace_depth == 1 and in_diag) {
                diag_ranges[diag_ranges_count] = .{ .start = current_diag, .end = i + 1 };
                diag_ranges_count += 1;
                in_diag = false;
            }
            if (brace_depth > 0) brace_depth -= 1;
        }
    }

    var d: usize = 0;
    while (d < diag_ranges_count and diagnostics.count < diagnostics.items.len) : (d += 1) {
        const diag_json = json[diag_ranges[d].start..diag_ranges[d].end];
        const range_start = findArrayStart(diag_json, "\"range\":{");
        const severity_start = findArrayStart(diag_json, "\"severity\":");
        const message_start = findArrayStart(diag_json, "\"message\":\"");

        if (range_start) |rs| {
            const line_start = findArrayStart(diag_json[rs..], "\"line\":") orelse continue;
            const line_str = diag_json[rs + line_start ..];
            const line = parseSimpleNumber(line_str);

            if (message_start) |ms| {
                const msg_end = findArrayStart(diag_json[ms..], "\"") orelse continue;
                const message = diag_json[ms + 1 .. ms + msg_end - 1];

                const severity = if (severity_start) |ss|
                    parseSimpleNumber(diag_json[ss..])
                else
                    1;

                var start_col: usize = 0;
                var end_col: usize = 1;

                const char_start = findArrayStart(diag_json[rs..], "\"character\":") orelse null;
                if (char_start) |cs| {
                    start_col = parseSimpleNumber(diag_json[rs + cs ..]);
                    end_col = start_col + 1;
                }

                diagnostics.add(line, start_col, end_col, @as(u8, @intCast(severity)), message);
            }
        }
    }
}

fn parseSimpleNumber(s: []const u8) usize {
    var result: usize = 0;
    var i: usize = 0;
    while (i < s.len and (s[i] < '0' or s[i] > '9')) : (i += 1) {}
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
        result = result * 10 + @as(usize, @intCast(s[i] - '0'));
    }
    return result;
}

fn getSemanticTokenColor(token_type: u32) u8 {
    return switch (token_type) {
        0 => ANSI_COLOR_KEYWORD,
        1 => ANSI_COLOR_TYPE,
        2 => ANSI_COLOR_CLASS,
        3 => ANSI_COLOR_NUMBER,
        4 => ANSI_COLOR_STRING,
        5 => ANSI_COLOR_COMMENT,
        6 => ANSI_COLOR_FUNCTION,
        7 => ANSI_COLOR_VARIABLE,
        8 => ANSI_COLOR_PARAMETER,
        9 => ANSI_COLOR_PROPERTY,
        else => ANSI_COLOR_DEFAULT,
    };
}

fn renderViewport(data: [*]const u8, size: usize, line_offset: usize, screen_buffer: *ScreenBuffer, editor_state: *EditorState) void {
    // Clear the current buffer
    screen_buffer.current = [_][SCREEN_COLS]u8{[_]u8{0} ** SCREEN_COLS} ** SCREEN_ROWS;

    // Enhanced status bar (row 0)
    var status_col: usize = 0;

    // Mode indicator
    const mode_str = if (editor_state.insert_mode) "[INSERT] " else if (editor_state.search_mode) "[SEARCH] " else "[NORMAL] ";
    for (mode_str) |c| {
        screen_buffer.setChar(0, status_col, c);
        status_col += 1;
        if (status_col >= SCREEN_COLS) break;
    }

    // Line and column (1-based)
    const line_num = editor_state.cursor_row + 1;
    const col_num = editor_state.cursor_col + 1;
    var num_buf: [16]u8 = undefined;
    var num_len: usize = 0;

    // Convert line number to string
    var n = line_num;
    if (n == 0) {
        num_buf[num_len] = '0';
        num_len += 1;
    } else {
        var digits: [16]u8 = undefined;
        var digit_count: usize = 0;
        while (n > 0) : (n /= 10) {
            digits[digit_count] = '0' + @as(u8, @intCast(n % 10));
            digit_count += 1;
        }
        var d: usize = digit_count;
        while (d > 0) : (d -= 1) {
            num_buf[num_len] = digits[d - 1];
            num_len += 1;
        }
    }

    // Add colon
    num_buf[num_len] = ',';
    num_len += 1;

    // Convert column number to string
    n = col_num;
    if (n == 0) {
        num_buf[num_len] = '0';
        num_len += 1;
    } else {
        var digits: [16]u8 = undefined;
        var digit_count: usize = 0;
        while (n > 0) : (n /= 10) {
            digits[digit_count] = '0' + @as(u8, @intCast(n % 10));
            digit_count += 1;
        }
        var d: usize = digit_count;
        while (d > 0) : (d -= 1) {
            num_buf[num_len] = digits[d - 1];
            num_len += 1;
        }
    }

    for (num_buf[0..num_len]) |c| {
        screen_buffer.setChar(0, status_col, c);
        status_col += 1;
        if (status_col >= SCREEN_COLS) break;
    }

    // File size
    const size_str = " | ";
    for (size_str) |c| {
        screen_buffer.setChar(0, status_col, c);
        status_col += 1;
        if (status_col >= SCREEN_COLS) break;
    }

    // File size in bytes
    n = size;
    if (n == 0) {
        screen_buffer.setChar(0, status_col, '0');
        status_col += 1;
    } else {
        var digits: [16]u8 = undefined;
        var digit_count: usize = 0;
        while (n > 0) : (n /= 10) {
            digits[digit_count] = '0' + @as(u8, @intCast(n % 10));
            digit_count += 1;
        }
        var d: usize = digit_count;
        while (d > 0) : (d -= 1) {
            screen_buffer.setChar(0, status_col, digits[d - 1]);
            status_col += 1;
            if (status_col >= SCREEN_COLS) break;
        }
    }

    // Modified indicator
    const mod_str = if (editor_state.modified) " [MODIFIED]" else " ";
    for (mod_str) |c| {
        screen_buffer.setChar(0, status_col, c);
        status_col += 1;
        if (status_col >= SCREEN_COLS) break;
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
        var col: usize = 0;
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

    // Process LSP messages
    if (editor_state.lsp_active) {
        while (editor_state.lsp_client.readMessage()) |msg| {
            if (containsString(msg, "\"method\":\"textDocument/publishDiagnostics\"")) {
                parseDiagnostics(msg, &editor_state.diagnostics);
            } else if (containsString(msg, "\"result\":{")) {
                if (containsString(msg, "\"data\":[")) {
                    const data_start = findArrayStart(msg, "\"data\":[");
                    if (data_start) |start| {
                        var data_buf: [4096]u32 = undefined;
                        const data_len = parseUint32Array(msg[start..], &data_buf);
                        editor_state.semantic_tokens.parse(data_buf[0..data_len]);
                    }
                }
            }
        }
    }

    // Set footer line (last row)
    const total_lines = countLines(data, size);
    const footer_start = "Lines: ";
    var col: usize = 0;
    for (footer_start) |c| {
        screen_buffer.setChar(SCREEN_ROWS - 1, col, c);
        col += 1;
        if (col >= SCREEN_COLS) break;
    }

    // Add line count
    var buf: [20]u8 = undefined;
    var len: usize = 0;
    var line_count = total_lines;
    if (line_count == 0) {
        buf[len] = '0';
        len += 1;
    } else {
        var digits: [20]u8 = undefined;
        var digit_count: usize = 0;
        while (line_count > 0) : (line_count /= 10) {
            digits[digit_count] = '0' + @as(u8, @intCast(line_count % 10));
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
    const base_footer = " | /search n/N next/prev";
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
        const edit_help = ", Enter split";
        for (edit_help) |c| {
            footer_buf[footer_len] = c;
            footer_len += 1;
        }
    } else {
        const normal_help = ", dd del, J join, PgUp/Dn";
        for (normal_help) |c| {
            footer_buf[footer_len] = c;
            footer_len += 1;
        }
    }
    const rest_footer = ", w/b/e words, gg/G, :<num> goto, h/j/k/l move, BS/Del, Ctrl+Z undo, :w save, :lsp <server>, q quit";
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
        const screen_row = 1 + (editor_state.cursor_row - editor_state.line_offset); // +1 for status line
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
            data[i] = data[i + 1];
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

fn deleteChar(data: [*]u8, file_size: usize, editor_state: *EditorState, backspace: bool) void {
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

    // For backspace, delete character before cursor
    if (backspace) {
        if (byte_offset == 0) return; // At start of file
        byte_offset -= 1;
        // Check if we're at start of line
        if (data[byte_offset] == '\n') {
            // Don't delete newline (for now, simple implementation)
            return;
        }
    }

    // Record deleted character before shifting
    const deleted_char = data[byte_offset];

    // Shift everything left
    if (byte_offset < file_size) {
        var i: usize = byte_offset;
        while (i < file_size - 1) {
            data[i] = data[i + 1];
            i += 1;
        }
        data[file_size - 1] = 0; // Clear last byte

        // Record operation for undo
        recordOperation(editor_state, .{ .op_type = .delete, .position = byte_offset, .char = deleted_char });

        // Update cursor position
        if (backspace and editor_state.cursor_col > 0) {
            editor_state.cursor_col -= 1;
        }
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
    return countLines(data, file_size) + 1;
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

const CursorMove = enum { up, down, left, right, home, end, page_up, page_down, page_begin, page_end, word_next, word_prev, word_end };

fn moveCursor(data: [*]const u8, file_size: usize, editor_state: *EditorState, move: CursorMove) void {
    const max_col = getLineLength(data, file_size, editor_state.cursor_row);
    const viewport_rows: usize = 20;

    switch (move) {
        .up => {
            if (editor_state.cursor_row > 0) {
                editor_state.cursor_row -= 1;
                editor_state.cursor_col = @min(editor_state.cursor_col, getLineLength(data, file_size, editor_state.cursor_row));
            }
        },
        .down => {
            const total_lines = getTotalLines(data, file_size);
            if (editor_state.cursor_row < total_lines - 1) {
                editor_state.cursor_row += 1;
                editor_state.cursor_col = @min(editor_state.cursor_col, getLineLength(data, file_size, editor_state.cursor_row));
            }
        },
        .left => {
            if (editor_state.cursor_col > 0) {
                editor_state.cursor_col -= 1;
            }
        },
        .right => {
            if (editor_state.cursor_col < max_col) {
                editor_state.cursor_col += 1;
            }
        },
        .home => {
            editor_state.cursor_col = 0;
        },
        .end => {
            editor_state.cursor_col = max_col;
        },
        .page_up => {
            if (editor_state.line_offset >= viewport_rows) {
                editor_state.line_offset -= viewport_rows;
                if (editor_state.cursor_row > editor_state.line_offset + viewport_rows - 1) {
                    editor_state.cursor_row = editor_state.line_offset + viewport_rows - 1;
                }
            } else {
                editor_state.line_offset = 0;
                editor_state.cursor_row = 0;
            }
        },
        .page_down => {
            const total_lines = getTotalLines(data, file_size);
            const max_offset = if (total_lines > viewport_rows) total_lines - viewport_rows else 0;
            if (editor_state.line_offset < max_offset) {
                editor_state.line_offset += viewport_rows;
                if (editor_state.line_offset > max_offset) {
                    editor_state.line_offset = max_offset;
                }
                if (editor_state.cursor_row < editor_state.line_offset) {
                    editor_state.cursor_row = editor_state.line_offset;
                }
            }
        },
        .page_begin => {
            editor_state.line_offset = 0;
            editor_state.cursor_row = 0;
            editor_state.cursor_col = 0;
        },
        .page_end => {
            const total_lines = getTotalLines(data, file_size);
            editor_state.line_offset = if (total_lines > viewport_rows) total_lines - viewport_rows else 0;
            editor_state.cursor_row = if (total_lines > 0) total_lines - 1 else 0;
            editor_state.cursor_col = getLineLength(data, file_size, editor_state.cursor_row);
        },
        .word_next => {
            var pos = getByteOffset(data, file_size, editor_state.cursor_row, editor_state.cursor_col);
            const line_end = findLineEnd(data, file_size, editor_state.cursor_row);

            while (pos < line_end and !isWordChar(data[pos])) : (pos += 1) {}
            while (pos < line_end and isWordChar(data[pos])) {
                pos += 1;
            }

            const new_pos = getPositionFromByteOffset(data, file_size, pos);
            editor_state.cursor_row = new_pos.row;
            editor_state.cursor_col = new_pos.col;
        },
        .word_prev => {
            var pos = getByteOffset(data, file_size, editor_state.cursor_row, editor_state.cursor_col);
            if (pos > 0) pos -= 1;

            while (pos > 0 and !isWordChar(data[pos])) : (pos -= 1) {}
            while (pos > 0 and isWordChar(data[pos])) {
                pos -= 1;
            }
            if (pos > 0 and !isWordChar(data[pos])) pos += 1;

            const new_pos = getPositionFromByteOffset(data, file_size, pos);
            editor_state.cursor_row = new_pos.row;
            editor_state.cursor_col = new_pos.col;
        },
        .word_end => {
            var pos = getByteOffset(data, file_size, editor_state.cursor_row, editor_state.cursor_col);
            const line_end = findLineEnd(data, file_size, editor_state.cursor_row);

            while (pos < line_end and isWordChar(data[pos])) {
                pos += 1;
            }
            while (pos < line_end and !isWordChar(data[pos])) {
                pos += 1;
            }

            if (pos > 0) pos -= 1;
            const new_pos = getPositionFromByteOffset(data, file_size, pos);
            editor_state.cursor_row = new_pos.row;
            editor_state.cursor_col = new_pos.col;
        },
    }
}

fn isWordChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

const Position = struct { row: usize, col: usize };

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
    return .{ .row = row, .col = col };
}

fn findLineEnd(data: [*]const u8, file_size: usize, line: usize) usize {
    var current_line: usize = 0;
    var byte_offset: usize = 0;
    while (current_line < line and byte_offset < file_size) : (current_line += 1) {
        while (byte_offset < file_size and data[byte_offset] != '\n') : (byte_offset += 1) {}
        if (byte_offset < file_size and data[byte_offset] == '\n') {
            byte_offset += 1;
        }
    }
    return byte_offset;
}

fn gotoLine(editor_state: *EditorState, data: [*]const u8, file_size: usize, line: usize) void {
    const total_lines = getTotalLines(data, file_size);
    const target_line = if (line == 0 or line > total_lines) total_lines - 1 else line - 1;
    editor_state.cursor_row = target_line;
    editor_state.cursor_col = getLineLength(data, file_size, target_line);
    ensureCursorVisible(editor_state, data, file_size);
}

fn ensureCursorVisible(editor_state: *EditorState, data: [*]const u8, file_size: usize) void {
    _ = data;
    _ = file_size;
    const viewport_rows: usize = 20;

    if (editor_state.cursor_row < editor_state.line_offset) {
        editor_state.line_offset = editor_state.cursor_row;
    } else if (editor_state.cursor_row >= editor_state.line_offset + viewport_rows) {
        editor_state.line_offset = editor_state.cursor_row - viewport_rows + 1;
    }
}

const LineOperation = struct {
    op_type: enum { insert_line, delete_line, join_line },
    position: usize, // byte offset
    deleted_content: []const u8, // for undo
};

const LINE_OP_BUFFER_SIZE = 4096;

fn splitLine(data: [*]u8, file_size: usize, editor_state: *EditorState) void {
    // Find byte offset at cursor position
    var byte_offset: usize = 0;
    var current_line: usize = 0;

    while (current_line < editor_state.cursor_row and byte_offset < file_size) {
        while (byte_offset < file_size and data[byte_offset] != '\n') {
            byte_offset += 1;
        }
        if (byte_offset < file_size) {
            byte_offset += 1;
            current_line += 1;
        }
    }

    var col: usize = 0;
    while (col < editor_state.cursor_col and byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
        col += 1;
    }

    // Shift everything right to make room for newline
    if (byte_offset < file_size - 1) {
        var i: usize = file_size;
        while (i > byte_offset) {
            data[i] = data[i - 1];
            i -= 1;
        }
        data[byte_offset] = '\n';

        editor_state.cursor_row += 1;
        editor_state.cursor_col = 0;
    }
}

fn deleteLine(data: [*]u8, file_size: usize, editor_state: *EditorState) void {
    // Find line start and end
    var byte_offset: usize = 0;
    var current_line: usize = 0;

    while (current_line < editor_state.cursor_row and byte_offset < file_size) {
        while (byte_offset < file_size and data[byte_offset] != '\n') {
            byte_offset += 1;
        }
        if (byte_offset < file_size) {
            byte_offset += 1;
            current_line += 1;
        }
    }

    const line_start = byte_offset;

    // Find end of line (including newline)
    while (byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
    }

    const line_end = byte_offset;
    const has_newline = byte_offset < file_size and data[byte_offset] == '\n';
    const delete_len = if (has_newline) line_end - line_start + 1 else line_end - line_start;

    // Shift everything left
    var i: usize = line_start;
    while (i < file_size - delete_len) {
        data[i] = data[i + delete_len];
        i += 1;
    }
    for (i..file_size) |j| {
        data[j] = 0;
    }
}

fn joinLine(data: [*]u8, file_size: usize, editor_state: *EditorState) void {
    // Find current line end (including newline)
    var byte_offset: usize = 0;
    var current_line: usize = 0;

    while (current_line < editor_state.cursor_row and byte_offset < file_size) {
        while (byte_offset < file_size and data[byte_offset] != '\n') {
            byte_offset += 1;
        }
        if (byte_offset < file_size) {
            byte_offset += 1;
            current_line += 1;
        }
    }

    // Find current line end
    const line_start = byte_offset;
    while (byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
    }

    // If we're at the last line, nothing to join
    if (byte_offset >= file_size) return;

    // byte_offset is at the newline of current line
    // Skip the newline
    byte_offset += 1;

    // Find end of next line
    const next_line_end = byte_offset;
    while (byte_offset < file_size and data[byte_offset] != '\n') {
        byte_offset += 1;
    }

    const delete_len = next_line_end - line_start;

    // Shift everything left to remove the newline
    var i: usize = line_start;
    while (i < file_size - delete_len) {
        data[i] = data[i + delete_len];
        i += 1;
    }
    for (i..file_size) |j| {
        data[j] = 0;
    }
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
    while (offset >= 0) {
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

fn offsetToRowCol(data: [*]const u8, file_size: usize, offset: usize) struct { row: usize, col: usize } {
    var byte_offset: usize = 0;
    var row: usize = 0;

    while (byte_offset < offset and byte_offset < file_size) {
        if (data[byte_offset] == '\n') {
            row += 1;
        }
        byte_offset += 1;
    }

    // Find start of line
    var line_start: usize = offset;
    while (line_start > 0 and data[line_start - 1] != '\n') {
        line_start -= 1;
    }

    return .{ .row = row, .col = offset - line_start };
}

fn executeSearch(data: [*]const u8, file_size: usize, editor_state: *EditorState) void {
    if (editor_state.search_len == 0) return;

    const pattern = editor_state.search_buffer[0..editor_state.search_len];
    const match_offset = searchForward(data, file_size, pattern, editor_state.search_match_offset + 1);

    if (match_offset) |offset| {
        const pos = offsetToRowCol(data, file_size, offset);
        editor_state.search_match_row = pos.row;
        editor_state.search_match_col = pos.col;
        editor_state.search_match_offset = offset;
        editor_state.cursor_row = pos.row;
        editor_state.cursor_col = pos.col;
        ensureCursorVisible(editor_state, data, file_size);
    } else {
        // Wrap to beginning
        const wrap_offset = searchForward(data, file_size, pattern, 0);
        if (wrap_offset) |offset| {
            const pos = offsetToRowCol(data, file_size, offset);
            editor_state.search_match_row = pos.row;
            editor_state.search_match_col = pos.col;
            editor_state.search_match_offset = offset;
            editor_state.cursor_row = pos.row;
            editor_state.cursor_col = pos.col;
            ensureCursorVisible(editor_state, data, file_size);
        }
    }
}

fn executeSearchBackward(data: [*]const u8, file_size: usize, editor_state: *EditorState) void {
    if (editor_state.search_len == 0) return;

    const pattern = editor_state.search_buffer[0..editor_state.search_len];
    const start_offset = if (editor_state.search_match_offset > 0) editor_state.search_match_offset else file_size;
    const match_offset = searchBackward(data, file_size, pattern, start_offset);

    if (match_offset) |offset| {
        const pos = offsetToRowCol(data, file_size, offset);
        editor_state.search_match_row = pos.row;
        editor_state.search_match_col = pos.col;
        editor_state.search_match_offset = offset;
        editor_state.cursor_row = pos.row;
        editor_state.cursor_col = pos.col;
        ensureCursorVisible(editor_state, data, file_size);
    } else {
        // Wrap to end
        const wrap_offset = searchBackward(data, file_size, pattern, file_size);
        if (wrap_offset) |offset| {
            const pos = offsetToRowCol(data, file_size, offset);
            editor_state.search_match_row = pos.row;
            editor_state.search_match_col = pos.col;
            editor_state.search_match_offset = offset;
            editor_state.cursor_row = pos.row;
            editor_state.cursor_col = pos.col;
            ensureCursorVisible(editor_state, data, file_size);
        }
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

fn startLspServer(editor_state: *EditorState, filename: [*]const u8, data: [*]const u8, file_size: usize) void {
    if (editor_state.lsp_active) {
        _ = editor_state.lsp_client.sendShutdown();
        _ = editor_state.lsp_client.sendExit();
        editor_state.lsp_client.stopServer();
        editor_state.lsp_active = false;
    }

    const server_name = editor_state.lsp_server_name[0..nullTerminatedLength(&editor_state.lsp_server_name)];
    if (server_name.len == 0) {
        return;
    }
    var is_none = true;
    if (server_name.len == 4) {
        const none_str = "none";
        for (0..4) |i| {
            const sn = server_name[i];
            const ns = none_str[i];
            const sn_lower = if (sn >= 'A' and sn <= 'Z') sn + 32 else sn;
            if (sn_lower != ns) {
                is_none = false;
                break;
            }
        }
    } else {
        is_none = false;
    }
    if (is_none) {
        return;
    }

    const server_info = getLspServerByName(server_name);
    if (server_info == null) {
        const error_msg = "Unknown LSP server. Available: zls, clangd, pylsp, rust-analyzer, gopls, none\n";
        rawWrite(STDOUT_FILENO, error_msg, error_msg.len);
        return;
    }

    const uri = makeFileUri(filename);
    const uri_len = uri.len;
    if (uri_len < 256) {
        @memcpy(editor_state.lsp_uri[0..uri_len], uri[0..uri_len]);
        editor_state.lsp_uri[uri_len] = 0;
    }

    if (editor_state.lsp_client.startServer(server_info.?.server_name, server_info.?.args)) {
        editor_state.lsp_active = true;

        const language_id = detectLanguageId(filename);
        const text = data[0..file_size];

        if (editor_state.lsp_client.sendInitialize(&editor_state.lsp_uri)) {
            if (editor_state.lsp_client.waitForInitialize()) {
                _ = editor_state.lsp_client.sendInitialized();
                _ = editor_state.lsp_client.sendDidOpen(&editor_state.lsp_uri, language_id, editor_state.file_version, text);
                _ = editor_state.lsp_client.requestSemanticTokens(&editor_state.lsp_uri);
            }
        }
    } else {
        const error_msg = "Failed to start LSP server\n";
        rawWrite(STDOUT_FILENO, error_msg, error_msg.len);
        editor_state.lsp_active = false;
    }
}

comptime {
    asm (
        \\.global _start
        \\_start:
        \\  xor %rbp, %rbp
        \\  mov %rsp, %rdi
        \\  and $-16, %rsp
        \\  call zig_start
        \\  mov %rax, %rdi
        \\  mov $60, %rax
        \\  syscall
    );
}

export fn zig_start(sp: usize) usize {
    const argc = @as(*usize, @ptrFromInt(sp)).*;
    const argv = @as([*][*:0]u8, @ptrFromInt(sp + 8));
        const args = struct { argc: usize, argv: [*][*:0]u8 }{ .argc = argc, .argv = argv };
    
        const default_file = "/tmp/test_file.txt";
        const filename_ptr: [*:0]const u8 = if (args.argc > 1) args.argv[1] else default_file;
    
        const fd = rawOpen(filename_ptr, O_RDWR, 0);
    
    if (fd < 0) {
        const error_msg = "Error: Could not open file\n";
        rawWrite(STDOUT_FILENO, error_msg, error_msg.len);
        return 1;
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
        return 1;
    }

    const close_result = rawClose(fd_usize);
    _ = close_result;

    var editor_state: EditorState = .{};
    editor_state.file_size = file_size;
    editor_state.aligned_size = aligned_size;
    editor_state.filename = filename_ptr;
    editor_state.lsp_client = LSPClient.init();
    editor_state.semantic_tokens = SemanticTokens.init();
    editor_state.diagnostics = Diagnostics.init();

    var in_command: bool = false;

    if (mapped_ptr) |data| {
        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
    }

    rawWrite(STDOUT_FILENO, ansi_mouse.ENABLE_MOUSE, ansi_mouse.ENABLE_MOUSE.len);

    var raw_buffer: [32]u8 = undefined; // Support SGR mouse sequences
    var normal_mode_buffer: [1]u8 = undefined;
    while (true) {
        const read_result = rawRead(STDIN_FILENO, &raw_buffer, 1);
        if (raw_buffer[0] == 'q') {
            rawWrite(STDOUT_FILENO, ansi_mouse.DISABLE_MOUSE, ansi_mouse.DISABLE_MOUSE.len);
            break;
        }
        if (read_result > 0) {
            if (mapped_ptr) |data| {
                // Handle Escape Sequences Globally
                if (raw_buffer[0] == 0x1b) {
                    var seq_len: usize = 1;
                    const n1 = rawRead(STDIN_FILENO, raw_buffer[1..].ptr, 1);
                    if (n1 > 0) {
                        seq_len += 1;
                        if (raw_buffer[1] == '[') {
                            const n2 = rawRead(STDIN_FILENO, raw_buffer[2..].ptr, 1);
                            if (n2 > 0) {
                                seq_len += 1;
                                if (raw_buffer[2] == '<') {
                                    // Mouse Sequence: \x1b[<...
                                    var k: usize = 3;
                                    while (k < 32) {
                                        const nm = rawRead(STDIN_FILENO, raw_buffer[k..].ptr, 1);
                                        if (nm == 0) break;
                                        seq_len += 1;
                                        if (raw_buffer[k] == 'M' or raw_buffer[k] == 'm') break;
                                        k += 1;
                                    }
                                    
                                    if (mouse.parseSgrMouse(raw_buffer[0..seq_len])) |event| {
                                        if (event.pressed) {
                                            if (event.button == 0) { // Left Click
                                                if (event.row > 1) { // Skip status bar
                                                    const target_row = editor_state.line_offset + (event.row - 2);
                                                    editor_state.cursor_row = @min(target_row, getTotalLines(data, file_size) - 1);
                                                    editor_state.cursor_col = @min(event.col - 1, getLineLength(data, file_size, editor_state.cursor_row));
                                                }
                                            } else if (event.button == 64) { // Scroll Up
                                                moveCursor(data, file_size, &editor_state, .up);
                                                moveCursor(data, file_size, &editor_state, .up);
                                                moveCursor(data, file_size, &editor_state, .up);
                                            } else if (event.button == 65) { // Scroll Down
                                                moveCursor(data, file_size, &editor_state, .down);
                                                moveCursor(data, file_size, &editor_state, .down);
                                                moveCursor(data, file_size, &editor_state, .down);
                                            }
                                        }
                                        ensureCursorVisible(&editor_state, data, file_size);
                                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                                    }
                                    continue;
                                } else {
                                    // Handle Arrows and other CSI sequences globally
                                    if (raw_buffer[2] == 'A') moveCursor(data, file_size, &editor_state, .up);
                                    if (raw_buffer[2] == 'B') moveCursor(data, file_size, &editor_state, .down);
                                    if (raw_buffer[2] == 'C') moveCursor(data, file_size, &editor_state, .right);
                                    if (raw_buffer[2] == 'D') moveCursor(data, file_size, &editor_state, .left);
                                    if (raw_buffer[2] == 'H') moveCursor(data, file_size, &editor_state, .home);
                                    if (raw_buffer[2] == 'F') moveCursor(data, file_size, &editor_state, .end);
                                    if (raw_buffer[2] == '3') {
                                        const n3 = rawRead(STDIN_FILENO, raw_buffer[3..].ptr, 1);
                                        if (n3 > 0 and raw_buffer[3] == '~') {
                                            deleteChar(data, editor_state.file_size, &editor_state, false);
                                            editor_state.modified = true;
                                        }
                                    }
                                    ensureCursorVisible(&editor_state, data, file_size);
                                    renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                                    continue;
                                }
                            }
                        } else {
                            // Just ESC
                            if (editor_state.insert_mode) {
                                editor_state.insert_mode = false;
                                renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                            } else if (editor_state.search_mode) {
                                editor_state.search_mode = false;
                                editor_state.search_len = 0;
                                renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                            } else if (in_command) {
                                in_command = false;
                                editor_state.command_len = 0;
                            }
                            continue;
                        }
                    }
                }

                // Handle Ctrl+Z (undo) - ASCII 26
                if (raw_buffer[0] == 26) {
                    undoOperation(data, &editor_state);
                    renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                } else if (editor_state.search_mode) {
                    // Search mode input
                    if (raw_buffer[0] == 13) { // Enter to execute search
                        executeSearch(data, file_size, &editor_state);
                        editor_state.search_mode = false;
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'n') { // Next match
                        executeSearch(data, file_size, &editor_state);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'N') { // Previous match
                        executeSearchBackward(data, file_size, &editor_state);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 8 and editor_state.search_len > 0) { // Backspace
                        editor_state.search_len -= 1;
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] >= 32 and raw_buffer[0] <= 126 and editor_state.search_len < SEARCH_BUFFER_SIZE) {
                        // Add character to search buffer
                        editor_state.search_buffer[editor_state.search_len] = raw_buffer[0];
                        editor_state.search_len += 1;
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    }
                } else if (raw_buffer[0] == ':') {
                    in_command = true;
                    editor_state.command_len = 0;
                } else if (in_command) {
                    if (raw_buffer[0] == 13) { // Enter to execute command
                        const cmd = editor_state.command_buffer[0..editor_state.command_len];
                        if (cmd.len > 3 and cmd[0] == 'l' and cmd[1] == 's' and cmd[2] == 'p') {
                            const server_name = cmd[4..];
                            if (server_name.len > 0) {
                                @memcpy(editor_state.lsp_server_name[0..server_name.len], server_name);
                                editor_state.lsp_server_name[server_name.len] = 0;
                                startLspServer(&editor_state, filename_ptr, data, file_size);
                            }
                        } else if (cmd.len > 3 and cmd[0] == 's' and cmd[1] == 'e' and cmd[2] == 't') {
                            const option = cmd[4..];
                            if (eqStr(option, "all")) {
                                const info_msg = "Options: tabsize=<n>, syntaxhighlighting=<bool>, autolsp=<bool>, statusline=<bool>, linenumbers=<bool>, autoindent=<bool>, wraplines=<bool>\n";
                                rawWrite(STDOUT_FILENO, info_msg, info_msg.len);
                            } else if (option.len > 5 and option[4] == '=') {
                                const opt_name = option[0..4];
                                const opt_value = option[5..];
                                if (eqStr(opt_name, "tabs")) {
                                    editor_state.config.tab_size = parseNumber(opt_value);
                                } else if (eqStr(opt_name, "synt")) {
                                    editor_state.config.syntax_highlighting = true;
                                }
                            }
                        } else if (cmd.len > 0) {
                            var is_number = true;
                            var line_num: usize = 0;
                            for (cmd) |c| {
                                if (c < '0' or c > '9') {
                                    is_number = false;
                                    break;
                                }
                                line_num = line_num * 10 + @as(usize, @intCast(c - '0'));
                            }
                            if (is_number and line_num > 0) {
                                gotoLine(&editor_state, data, file_size, line_num);
                                renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                            }
                        }
                        in_command = false;
                        editor_state.command_len = 0;
                    } else if (raw_buffer[0] == 8 and editor_state.command_len > 0) { // Backspace
                        editor_state.command_len -= 1;
                    } else if (raw_buffer[0] >= 32 and raw_buffer[0] <= 126 and editor_state.command_len < 64) {
                        editor_state.command_buffer[editor_state.command_len] = raw_buffer[0];
                        editor_state.command_len += 1;
                    }
                } else if (raw_buffer[0] == '/') {
                    // Enter search mode
                    editor_state.search_mode = true;
                    editor_state.search_len = 0;
                    renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                } else if (in_command and raw_buffer[0] == 'w') {
                    _ = saveFile(data, aligned_size, editor_state.modified, &editor_state);
                    in_command = false;
                } else if (!editor_state.insert_mode) {
                    // Handle multi-key commands like 'dd'
                    if (raw_buffer[0] == 'd') {
                        const read_result2 = rawRead(STDIN_FILENO, &normal_mode_buffer, 1);
                        if (read_result2 > 0 and normal_mode_buffer[0] == 'd') {
                            // dd command - delete current line
                            deleteLine(data, file_size, &editor_state);
                            editor_state.modified = true;
                            ensureCursorVisible(&editor_state, data, file_size);
                            renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                        }
                    } else if (raw_buffer[0] == 'J') {
                        // J command - join lines
                        joinLine(data, file_size, &editor_state);
                        editor_state.modified = true;
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'i') {
                        editor_state.insert_mode = true;
                        editor_state.cursor_row = 0;
                        editor_state.cursor_col = 0;
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'j') {
                        // j key - scroll down
                        if (editor_state.line_offset < countLines(data, file_size) - 20) {
                            const new_offset = editor_state.line_offset + 1;
                            editor_state.line_offset = new_offset;
                            renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                        }
                    } else if (raw_buffer[0] == 'k') {
                        if (editor_state.line_offset > 0) {
                            const new_offset = editor_state.line_offset - 1;
                            editor_state.line_offset = new_offset;
                            renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                        }
                    } else if (raw_buffer[0] == 'h') { // Move left (vim-style)
                        moveCursor(data, file_size, &editor_state, .left);
                        ensureCursorVisible(&editor_state, data, file_size);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'l') { // Move right (vim-style)
                        moveCursor(data, file_size, &editor_state, .right);
                        ensureCursorVisible(&editor_state, data, file_size);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == '0') { // Home (vim-style)
                        moveCursor(data, file_size, &editor_state, .home);
                        ensureCursorVisible(&editor_state, data, file_size);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == '$') { // End (vim-style)
                        moveCursor(data, file_size, &editor_state, .end);
                        ensureCursorVisible(&editor_state, data, file_size);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'g') { // First g for gg
                        const read_more = rawRead(STDIN_FILENO, raw_buffer[1..].ptr, 1);
                        if (read_more > 0 and raw_buffer[1] == 'g') {
                            moveCursor(data, file_size, &editor_state, .page_begin);
                            renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                        }
                    } else if (raw_buffer[0] == 'G') { // Goto end
                        moveCursor(data, file_size, &editor_state, .page_end);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'w') { // Word next
                        moveCursor(data, file_size, &editor_state, .word_next);
                        ensureCursorVisible(&editor_state, data, file_size);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'b') { // Word previous
                        moveCursor(data, file_size, &editor_state, .word_prev);
                        ensureCursorVisible(&editor_state, data, file_size);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 'e') { // Word end
                        moveCursor(data, file_size, &editor_state, .word_end);
                        ensureCursorVisible(&editor_state, data, file_size);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 2) { // Ctrl+B - Page Up
                        moveCursor(data, file_size, &editor_state, .page_up);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 6) { // Ctrl+F - Page Down
                        moveCursor(data, file_size, &editor_state, .page_down);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    }
                } else if (editor_state.insert_mode) {
                    if (raw_buffer[0] == 8) { // Backspace (ASCII 8)
                        deleteChar(data, editor_state.file_size, &editor_state, true);
                        editor_state.modified = true;
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] == 13) { // Enter key
                        splitLine(data, file_size, &editor_state);
                        editor_state.modified = true;
                        ensureCursorVisible(&editor_state, data, file_size);
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    } else if (raw_buffer[0] >= 32 and raw_buffer[0] <= 126) { // Printable characters
                        insertChar(data, editor_state.file_size, &editor_state, raw_buffer[0]);
                        editor_state.modified = true;
                        renderViewport(data, file_size, editor_state.line_offset, &editor_state.screen_buffer, &editor_state);
                    }
                }
            }
        }
    }

    const exit_msg = "\x1b[2J\x1b[HGoodbye!\n";
    rawWrite(STDOUT_FILENO, exit_msg, exit_msg.len);

    if (editor_state.lsp_active) {
        _ = editor_state.lsp_client.sendShutdown();
        _ = editor_state.lsp_client.sendExit();
        editor_state.lsp_client.stopServer();
    }

    if (mapped_ptr) |data| {
        _ = rawMunmap(data, aligned_size);
    }

    return 0;
}
