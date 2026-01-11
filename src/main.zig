const Syscall = enum(usize) { write = 1, exit = 60, read = 0, open = 2, close = 3, fstat = 5, mmap = 9, munmap = 11 };
const STDIN_FILENO: usize = 0;
const STDOUT_FILENO: usize = 1;

const O_RDONLY: usize = 0;
const O_RDWR: usize = 2;
const PROT_READ: usize = 1;
const PROT_WRITE: usize = 2;
const PROT_READ_WRITE: usize = 3;
const MAP_PRIVATE: usize = 0x02;
const MAP_FAILED: isize = -1;

const PAGE_SIZE: usize = 4096;

inline fn syscall1(number: Syscall, arg1: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1));
}

inline fn syscall3(number: Syscall, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3));
}

inline fn syscall6(number: Syscall, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
          [arg6] "{r9}" (arg6));
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

inline fn syscall2(number: Syscall, arg1: usize, arg2: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2));
}

fn getPageSize() usize {
    return PAGE_SIZE;
}

fn alignUp(size: usize, alignment: usize) usize {
    return (size + alignment - 1) & ~(alignment - 1);
}

const welcome_msg = "Spectre-IDE: The 2026 Monster Editor\n======================================\nPhase 2 Active:\n  [x] Freestanding Entry (No LibC)\n  [x] Raw Mode TTY Driver\n  [x] Direct Syscalls\n  [ ] Memory-Mapped I/O (Zero-Copy)\n\nUsage: spectre-ide <filename>\nControls: 'q' to exit, j/k to scroll\n\n";

const Viewport = struct {
    rows: usize = 24,
    cols: usize = 80,
    line_offset: usize = 0,
    data: ?[*]u8 = null,
    size: usize = 0,
};

const EditorState = struct {
    viewport: Viewport = .{},
    filename: [*]const u8 = &.{},
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

fn renderViewport(data: [*]const u8, size: usize, line_offset: usize) void {
    const clear = "\x1b[2J\x1b[H";
    rawWrite(STDOUT_FILENO, clear, clear.len);
    
    const status = "\x1b[7m Spectre-IDE - Phase 2 (mmap) \x1b[0m\n";
    rawWrite(STDOUT_FILENO, status, status.len);
    
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
    
    while (current_line < rows and display_offset < size) : (current_line += 1) {
        const line_start = display_offset;
        while (display_offset < size and data[display_offset] != '\n') {
            display_offset += 1;
        }
        const line_len = display_offset - line_start;
        if (line_len > 0 and line_start + line_len <= size) {
            rawWrite(STDOUT_FILENO, data + line_start, line_len);
        }
        rawWrite(STDOUT_FILENO, "\n", 1);
        if (display_offset < size and data[display_offset] == '\n') {
            display_offset += 1;
        }
    }
    
    const total_lines = countLines(data, size);
    const line_info = "\x1b[90mLines: ";
    rawWrite(STDOUT_FILENO, line_info, line_info.len);
    
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
    rawWrite(STDOUT_FILENO, &buf, len);
    rawWrite(STDOUT_FILENO, " | j/k scroll, q exit\x1b[0m\n", 29);
}

export fn _start() noreturn {
    const test_file = "/tmp/test_file.txt";
    const filename_ptr = test_file;
    
    const fd = rawOpen(filename_ptr, O_RDWR, 0);
    if (fd < 0) {
        const error_msg = "Error: Could not open file\n";
        rawWrite(STDOUT_FILENO, error_msg, error_msg.len);
        rawExit(1);
    }
    
    var stat_buf: [144]u8 = undefined;
    const stat_result = syscall2(Syscall.fstat, @intCast(fd), @intFromPtr(&stat_buf));
    _ = stat_result;
    
    var file_size: usize = 0;
    const size_ptr: *usize = @ptrFromInt(@intFromPtr(&stat_buf) + 48);
    file_size = size_ptr.*;
    
    if (file_size == 0) file_size = 1024;
    
    const aligned_size = alignUp(file_size, getPageSize());
    
    const mapped_ptr = rawMmap(null, aligned_size, PROT_READ_WRITE, MAP_PRIVATE, @intCast(fd), 0);
    if (mapped_ptr == null) {
        const error_msg = "Error: mmap failed\n";
        rawWrite(STDOUT_FILENO, error_msg, error_msg.len);
        const close_result = rawClose(@intCast(fd));
        _ = close_result;
        rawExit(1);
    }
    
    const close_result = rawClose(@intCast(fd));
    _ = close_result;
    
    var line_offset: usize = 0;
    
    if (mapped_ptr) |data| {
        renderViewport(data, file_size, line_offset);
    }
    
    var buffer: [1]u8 = undefined;
    while (true) {
        _ = rawRead(STDIN_FILENO, &buffer, 1);
        if (buffer[0] == 'q') break;
        if (mapped_ptr) |data| {
            if (buffer[0] == 'j') {
                line_offset +%= 1;
                renderViewport(data, file_size, line_offset);
            } else if (buffer[0] == 'k' and line_offset > 0) {
                line_offset -= 1;
                renderViewport(data, file_size, line_offset);
            }
        }
    }
    
    rawExit(0);
}
