# Zig Reference Guide for Spectre-IDE Project

**Version:** Zig 0.16.0-dev.2145+ec25b1384
**Date:** 2026-01-12
**Project:** Spectre-IDE (Freestanding Editor)
**Phase:** Phase 13+ LSP Ready - Complete Editor

---

## Table of Contents

1. [Project Configuration](#project-configuration)
2. [Freestanding Mode](#freestanding-mode)
3. [Inline Assembly](#inline-assembly)
4. [Syscalls](#syscalls)
5. [Memory-Mapped I/O (mmap)](#memory-mapped-io-mmap)
6. [File Operations](#file-operations)
7. [Build System](#build-system)
8. [Types and Constants](#types-and-constants)
9. [Memory Management](#memory-management)
10. [ANSI Escape Sequences](#ansi-escape-sequences)
11. [Phase 2 Implementation Notes](#phase-2-implementation-notes)
12. [Phase 4 Implementation Notes](#phase-4-implementation-notes)
13. [LSP Client Integration](#lsp-client-integration)
14. [Common Issues and Solutions](#common-issues-and-solutions)
15. [Current Project Status](#current-project-status)

---

## Project Configuration

### Build System (build.zig)

The `build.zig` file configures Zig build system for freestanding targets:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Create module with source, target and optimize
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{
            .default_target = .{
                .cpu_arch = .x86_64,
                .os_tag = .freestanding,
            },
        }),
        .optimize = b.standardOptimizeOption(.{
            .preferred_optimize_mode = .ReleaseSmall,
        }),
        .unwind_tables = .none,
        .single_threaded = true,
    });

    const exe = b.addExecutable(.{
        .name = "spectre-ide",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Spectre-IDE");
    run_step.dependOn(&run_cmd.step);
}
```

**Key Module Options:**
- `unwind_tables = .none`: Disables unwind tables
- `single_threaded = true`: Disables threading support
- `optimize = .ReleaseSmall`: Optimizes for minimal binary size

---

## Freestanding Mode

Freestanding mode bypasses standard library (LibC) for minimal binary size.

### What is Freestanding Mode?

Freestanding targets have no operating system or standard library. The program must:
- Define its own `_start` entry point
- Handle all memory allocation manually
- Make direct system calls via assembly

### Entry Point

In freestanding mode, you define entry point manually using `export fn _start() noreturn`. No `callconv` is needed in Zig 0.16+.

```zig
export fn _start() noreturn {
    // Your code here
}
```

**Key Points:**
- `export`: Makes function visible to the linker
- `_start`: Standard entry point name (required for Linux)
- `noreturn`: Function never returns
- **Zig 0.16+**: No `callconv` needed - uses default C calling convention

---

## Inline Assembly

### Basic Syntax (Zig 0.16+)

```zig
inline fn syscall3(number: usize, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3)
        );
}
```

### Components

1. **Assembly Template:** The string containing assembly instructions
2. **Output Operands:** `: [output] "constraint" (variable)`
3. **Input Operands:** `: [name] "constraint" (expression)`
4. **Clobbers:** **NOTE:** In Zig 0.16+, explicit clobbers may not be supported the same way. Try omitting entirely or using minimal lists.

### Register Constraints

| Constraint | Description | Example |
|-------------|-------------|----------|
| `"r"` | Any general-purpose register | `"r" (value)` |
| `"a"` | RAX register | `"a" (value)` |
| `"D"` | RDI register | `"D" (fd)` |
| `"S"` | RSI register | `"S" (ptr)` |
| `"d"` | RDX register | `"d" (len)` |
| `"m"` | Memory operand | `"m" (*ptr)` |
| `"i"` | Immediate value | `"i" (1)` |

### Common Linux x86_64 Syscall Registers

| Syscall Number | RAX | RDI | RSI | RDX | R10 | R8 | R9 |
|---------------|------|------|------|------|-----|----|----|
| write | 1 | fd | buffer | count | - | - | - |
| read | 0 | fd | buffer | count | - | - | - |
| exit | 60 | error_code | - | - | - | - | - |
| open | 2 | filename | flags | mode | - | - | - |
| close | 3 | fd | - | - | - | - | - |
| fstat | 5 | fd | statbuf | - | - | - | - |
| mmap | 9 | addr | length | prot | flags | fd | offset |
| munmap | 11 | addr | length | - | - | - | - |

**Important:** For syscalls with 4+ arguments, R10 is used instead of RCX (since syscall instruction clobbers RCX).

---

## Syscalls

### Syscall Enum

```zig
const Syscall = enum(usize) {
    write = 1,
    read = 0,
    exit = 60,
    ioctl = 16,
    open = 2,
    close = 3,
    fstat = 5,
    mmap = 9,
    munmap = 11,
};
```

### Syscall Wrapper Functions

#### Three Argument Syscall

```zig
inline fn syscall3(number: usize, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3)
        );
}
```

#### Single Argument Syscall

```zig
inline fn syscall1(number: usize, arg1: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1)
        );
}
```

#### Two Argument Syscall

```zig
inline fn syscall2(number: usize, arg1: usize, arg2: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2)
        );
}
```

#### Six Argument Syscall (mmap)

```zig
inline fn syscall6(number: usize, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize)
        : [number] "{rax}" (number),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
          [arg6] "{r9}" (arg6)
        );
}
```

**Critical:** Use R10 for 4th argument (not RCX), R8 for 5th, R9 for 6th. This is because the `syscall` instruction clobbers RCX and R11.

### Common File Descriptor Constants

```zig
const STDIN_FILENO: usize = 0;
const STDOUT_FILENO: usize = 1;
const STDERR_FILENO: usize = 2;
```

---

## Build System

### Optimization Modes

| Mode | Description | Use Case |
|-------|-------------|-----------|
| `Debug` | No optimization, full safety | Development |
| `ReleaseFast` | Maximum speed, no safety | Production performance |
| `ReleaseSafe` | Optimize with safety checks | Production reliability |
| `ReleaseSmall` | Minimum binary size | Embedded/freestanding |

### Build Commands

```bash
# Build with release mode
/opt/zig/zig build -Drelease=true

# Build and run
/opt/zig/zig build run

# Clean build artifacts
/opt/zig/zig clean

# Check binary size
ls -lh zig-out/bin/spectre-ide
```

### Testing Phase 2 (mmap)

```bash
# Create test file
cat > /tmp/test_file.txt << 'EOF'
Line 1: Sample content
Line 2: More content
EOF

# Run editor (hardcoded to /tmp/test_file.txt)
./zig-out/bin/spectre-ide

# Controls: j/k to scroll, q to exit
```

---

## Memory-Mapped I/O (mmap)

### mmap Syscall Wrapper

```zig
const PAGE_SIZE: usize = 4096;
const MAP_FAILED: isize = -1;

fn rawMmap(addr: ?[*]u8, length: usize, prot: usize, flags: usize, fd: usize, offset: usize) ?[*]u8 {
    const addr_int = if (addr) |a| @intFromPtr(a) else 0;
    const result = syscall6(Syscall.mmap, addr_int, length, prot, flags, fd, offset);
    if (result == @as(usize, @bitCast(MAP_FAILED))) return null;
    return @ptrFromInt(result);
}
```

### mmap Constants

```zig
// Protection flags
const PROT_READ: usize = 0x1;
const PROT_WRITE: usize = 0x2;
const PROT_READ_WRITE: usize = 0x3;
const PROT_EXEC: usize = 0x4;

// Mapping flags
const MAP_PRIVATE: usize = 0x02;
const MAP_SHARED: usize = 0x01;
const MAP_ANONYMOUS: usize = 0x20;

// File access flags
const O_RDONLY: usize = 0x00;
const O_WRONLY: usize = 0x01;
const O_RDWR: usize = 0x02;
```

### Page Alignment Helper

```zig
fn alignUp(size: usize, alignment: usize) usize {
    return (size + alignment - 1) & ~(alignment - 1);
}
```

**Usage Example:**

```zig
const fd = rawOpen(filename, O_RDWR, 0);
const file_size = getFileSize(fd);
const aligned_size = alignUp(file_size, PAGE_SIZE);
const mapped_data = rawMmap(null, aligned_size, PROT_READ_WRITE, MAP_PRIVATE, fd, 0);
```

### Zero-Copy Benefits

- **No RAM Limit:** Files larger than physical RAM work via OS paging
- **Direct Editing:** Modify mmap'd memory; OS handles write-back
- **No memcpy:** File data accessed directly at virtual addresses

### msync - Flush to Disk

```zig
const MS_ASYNC: usize = 1;
const MS_SYNC: usize = 4;
const MS_INVALIDATE: usize = 2;

fn rawMsync(addr: [*]const u8, length: usize, flags: usize) isize {
    return @bitCast(syscall3(Syscall.msync, @intFromPtr(addr), length, flags));
}
```

**msync Flags:**
- `MS_ASYNC`: Schedule write-back but return immediately
- `MS_SYNC`: Write-back synchronously (blocks until complete)
- `MS_INVALIDATE`: Invalidate cached copies after sync

**Usage:**
```zig
// For MAP_SHARED mappings, changes are written back automatically
// Use msync to force immediate sync:
_ = rawMsync(data, aligned_size, MS_SYNC);

// For MAP_PRIVATE, changes never persist - need different approach
```

**Important:** Use `MAP_SHARED` with `msync` for persisting changes. `MAP_PRIVATE` creates copy-on-write mappings that don't write back to the original file.

---

## File Operations

### Opening Files

```zig
fn rawOpen(path: [*]const u8, flags: usize, mode: usize) isize {
    return @bitCast(syscall3(Syscall.open, @intFromPtr(path), flags, mode));
}
```

### Closing Files

```zig
fn rawClose(fd: usize) isize {
    return @bitCast(syscall1(Syscall.close, fd));
}
```

### Getting File Size (fstat)

```zig
fn getFileSize(fd: usize) usize {
    var stat_buf: [144]u8 = undefined;
    _ = syscall2(Syscall.fstat, fd, @intFromPtr(&stat_buf));
    
    // File size is at offset 48 in struct stat (x86_64 Linux)
    const size_ptr: *usize = @ptrFromInt(@intFromPtr(&stat_buf) + 48);
    return size_ptr.*;
}
```

**Stat Buffer Layout (struct stat):**
- Offset 48: st_size (file size in bytes)
- Total size: 144 bytes for x86_64

---

## Types and Constants

### Integer Types

| Type | Size | Signed | Range |
|-------|-------|---------|--------|
| `u8` | 8 bits | No | 0-255 |
| `u16` | 16 bits | No | 0-65535 |
| `u32` | 32 bits | No | 0-4294967295 |
| `u64` | 64 bits | No | 0-18446744073709551615 |
| `i32` | 32 bits | Yes | -2147483648 to 2147483647 |
| `i64` | 64 bits | Yes | ±9.2×10^18 |
| `usize` | Pointer-sized | No | Platform-dependent |
| `isize` | Pointer-sized | Yes | Platform-dependent |

### Extern Structs (C Interop)

```zig
const termios = extern struct {
    c_iflag: u32,
    c_oflag: u32,
    c_cflag: u32,
    c_lflag: u32,
    c_line: u8,
    c_cc: [32]u8,
};
```

**`extern struct` Features:**
- Guaranteed C-compatible layout
- No padding guarantees
- Fields are in declaration order

### Constants

```zig
// Terminal I/O constants
const TCGETS: usize = 0x5401;
const TCSETS: usize = 0x5402;
const ICANON: usize = 0x0002;
const ECHO: usize = 0x0008;

// ANSI escape sequences
const CLEAR_SCREEN = "\x1b[2J\x1b[H";
```

---

## Memory Management

### No Heap Allocation

In freestanding mode, there is no `std.heap.HeapAllocator`. All memory is:
- Stack-allocated (fixed-size arrays)
- Pre-allocated static buffers

### Fixed-Size Arrays

```zig
// Stack-allocated buffer (256KB total)
var buffer: [256 * 1024]u8 = undefined;

// Array of bytes for input
var input_buffer: [1]u8 = undefined;
```

### Static Variables

```zig
var original_termios: termios = undefined;
```

**Important:** Container-level variables in Zig have static lifetime.

### Type Conversions

```zig
// Convert pointer to integer for syscall
const ptr_int = @intFromPtr(ptr);

// Convert enum to integer
const syscall_num = @intFromEnum(Syscall.write); // Returns 1

// Convert integer to pointer
const data_ptr: [*]u8 = @ptrFromInt(addr);

// Convert between signed and unsigned
const unsigned: usize = @bitCast(signed_value);
```

### Reading Stack Pointer

```zig
export fn _start() noreturn {
    var sp: usize = 0;
    asm volatile ("mov %%rsp, %[sp]" : [sp] "=r" (sp));
    // sp now contains stack pointer value
}
```

**Use Cases:**
- Reading argc/argv from stack in freestanding mode
- Debugging stack usage
- Implementing custom allocators

---

## ANSI Escape Sequences

| Sequence | Effect |
|-----------|----------|
| `\x1b[2J` | Clear screen |
| `\x1b[H` | Move cursor to home |
| `\x1b[K` | Clear to end of line |
| `\x1b[7m` | Inverse video (highlight) |
| `\x1b[0m` | Reset all attributes |
| `\x1b[90m` | Bright black (gray) text |

---

## Phase 5 Implementation Notes

### Command-Line Argument Parsing

In freestanding mode, `argc` and `argv` are not provided as function parameters. They must be read directly from the stack at program entry.

### Stack Layout (x86_64 Linux)

```
[stack top]
+------------------+
| argc            | <- Stack pointer points here
+------------------+
| argv[0]         | <- Program name
+------------------+
| argv[1]         | <- First argument
+------------------+
| argv[2]         | <- Second argument
+------------------+
| NULL             | <- argv terminator
+------------------+
| envp            | <- Environment variables
+------------------+
| NULL             | <- envp terminator
+------------------+
```

### Reading Stack Pointer

```zig
fn parseArgcArgv() struct { argc: usize, argv: [*][*]u8 } {
    var sp: usize = 0;
    asm volatile ("mov %%rsp, %[sp]" : [sp] "=r" (sp));
    
    const argc = @as(*const usize, @ptrFromInt(sp)).*;
    const argv = @as([*][*]u8, @ptrFromInt(sp + @sizeOf(usize)));
    
    return .{ .argc = argc, .argv = argv };
}
```

### Important Considerations

1. **argc includes program name:** argv[0] is the program path, argv[1] is the first actual argument

2. **Pointer casting:** Stack contains addresses; use `@ptrFromInt()` and `@intFromPtr()` for safe conversion

3. **Null termination:** argv is terminated by a NULL pointer (not explicitly needed in basic usage)

4. **Default values:** Always provide fallback values when argc is 1 (program only)

5. **Error handling:** Check file open return values before attempting fstat/mmap operations

### Usage Pattern

```zig
const args = parseArgcArgv();
const default_file = "/tmp/test_file.txt";
const filename_ptr = if (args.argc > 1) args.argv[1] else default_file;
```

---

## Phase 2 Implementation Notes

### Key Discoveries

1. **Six-Argument Syscalls:** mmap requires 6 arguments. Use R10 for 4th arg, R8 for 5th, R9 for 6th. RCX is clobbered by `syscall` instruction.

2. **Page Alignment:** mmap length must be page-aligned (4096 bytes). Use `alignUp(size, PAGE_SIZE)` to ensure correct alignment.

3. **Null Pointer Handling:** For optional pointer arguments to syscalls, convert to integer: `const addr_int = if (addr) |a| @intFromPtr(a) else 0;`

4. **Stat Buffer Access:** File size is at offset 48 in `struct stat` (x86_64). Buffer must be at least 144 bytes.

5. **Viewport Rendering:** Track byte offsets, not line numbers, for efficient file traversal through mmap'd memory.

6. **Bounds Checking:** Always check pointer bounds when accessing mmap'd data: `if (line_start + line_len <= size) { ... }`

### Zero-Copy Architecture

The mmap approach allows:
- Files larger than physical RAM (OS paging)
- No buffer copying between file and memory
- Direct memory access: `data[byte_offset]`
- Automatic write-back to disk (with MAP_SHARED)

### Binary Size Growth

- Phase 1: 1.2KB (freestanding entry)
- Phase 2: 1.6KB (+400 bytes for mmap/fstat support)
- Phase 5: 1.7KB (+100 bytes for argv parsing)

Still well under 600KB target (97% under budget).

---

## Phase 6 Implementation Notes

### Cursor Position Tracking

Added cursor tracking to `EditorState` for file-level editing:

```zig
const EditorState = struct {
    cursor_row: usize = 0,  // Line in file (0-based)
    cursor_col: usize = 0,  // Column in line (0-based)
    insert_mode: bool = false,
    // ... other fields
};
```

### Insert Mode State Machine

Simple state machine for editing modes:

```zig
if (buffer[0] == 'i' and !editor_state.insert_mode) {
    editor_state.insert_mode = true;
    editor_state.cursor_row = line_offset;
    editor_state.cursor_col = 0;
} else if (editor_state.insert_mode) {
    if (buffer[0] == 27) { // ESC
        editor_state.insert_mode = false;
    } else {
        insertChar(data, editor_state.file_size, &editor_state, buffer[0]);
        editor_state.modified = true;
    }
}
```

### Character Insertion Logic

Simple character insertion by shifting bytes right:

```zig
fn insertChar(data: [*]u8, file_size: usize, editor_state: *EditorState, char: u8) void {
    // Find byte offset for cursor position
    var byte_offset: usize = 0;
    // Navigate to cursor_row and cursor_col
    // Shift bytes right from insertion point
    // Insert character
    // Update cursor_col += 1
}
```

**Limitations:** 
- No line wrapping yet
- Simple byte shifting (no gap buffer)
- File size must fit in allocated space

### Cursor Rendering

Position cursor in insert mode using ANSI escape:

```zig
if (editor_state.insert_mode) {
    const screen_row = 1 + (editor_state.cursor_row - line_offset);
    const screen_col = editor_state.cursor_col + 1;
    // ANSI: \x1b[row;colH
}
```

### Mode Indication

Show INSERT mode in status bar:

```zig
const footer = std.fmt.bufPrint(&footer_buf, 
    " | j/k scroll, i insert{}, :w save, q exit", 
    .{if (editor_state.insert_mode) " (INSERT)" else ""});
```

### Binary Size Growth

- Phase 1: 1.2KB
- Phase 2: 1.6KB (+400B mmap)
- Phase 5: 1.7KB (+100B argv)
- Phase 4: 1.7KB (+minimal msync)
- Phase 3: 1.7KB (+minimal double-buffer)
- Phase 6: 1.7KB (+minimal insert mode)
- Phase 7: 1.8KB (+100B undo buffer)

Still under 600KB target (99.7% under budget).

### Undo/Redo System Implementation

**Operation Tracking:**
```zig
const Operation = struct {
    op_type: enum { insert, delete },
    position: usize, // byte offset in file
    char: u8,       // character inserted/deleted
};

const UNDO_BUFFER_SIZE = 256;
const EditorState = struct {
    undo_buffer: [UNDO_BUFFER_SIZE]Operation,
    undo_index: usize = 0,
    undo_count: usize = 0,
    // ... other fields
};
```

**Recording Operations:**
```zig
fn recordOperation(editor_state: *EditorState, op: Operation) void {
    editor_state.undo_buffer[editor_state.undo_index] = op;
    editor_state.undo_index = (editor_state.undo_index + 1) % UNDO_BUFFER_SIZE;
    if (editor_state.undo_count < UNDO_BUFFER_SIZE) {
        editor_state.undo_count += 1;
    }
}
```

**Undo Implementation:**
```zig
fn undoOperation(data: [*]u8, editor_state: *EditorState) void {
    if (editor_state.undo_count == 0) return;

    editor_state.undo_index = if (editor_state.undo_index == 0) 
        UNDO_BUFFER_SIZE - 1 else editor_state.undo_index - 1;
    const op = editor_state.undo_buffer[editor_state.undo_index];
    editor_state.undo_count -= 1;

    if (op.op_type == .insert) {
        // Remove inserted character by shifting left
        // Update cursor position
    } else if (op.op_type == .delete) {
        // Re-insert deleted character by shifting right
    }
}
```

**Ctrl+Z Handling:**
- ASCII 26 (Ctrl+Z) triggers undo
- Only works in normal mode (not insert mode)
- Reverses last operation and updates display

**Memory Usage:** 256 operations × (1 + 8 + 1) = ~2.5KB for undo buffer

---

## Phase 7: Undo/Redo System Complete

## Advanced Features Roadmap

### Phase 7: Delete/Backspace Support

**Goal:** Enable character and line deletion in insert mode

**Tasks:**
- Handle backspace key (ASCII 8 or 127) in insert mode
- Handle delete key (escape sequences)
- Shift bytes left to remove characters
- Update cursor position after deletion
- Prevent deletion beyond file bounds

**Technical Details:**
```zig
fn deleteChar(data: [*]u8, file_size: usize, editor_state: *EditorState) void {
    // Find byte offset for cursor position
    // Shift bytes left from deletion point
    // Update cursor_col -= 1
}
```

### Phase 8: Cursor Movement

**Goal:** Free cursor movement within file content

**Tasks:**
- Handle arrow keys (escape sequences: \x1b[A, \x1b[B, etc.)
- Handle vim-style movement (h/j/k/l keys)
- Constrain cursor within file bounds
- Update viewport scrolling when cursor moves outside visible area
- Handle line wrapping for cursor positioning

**Technical Details:**
```zig
fn moveCursor(editor_state: *EditorState, direction: enum { up, down, left, right }) void {
    switch (direction) {
        .up => editor_state.cursor_row = @max(0, editor_state.cursor_row - 1),
        .down => editor_state.cursor_row = @min(max_row, editor_state.cursor_row + 1),
        // ... handle column movement within line bounds
    }
}
```

### Phase 9: Line Operations

**Goal:** Support line insertion and deletion

**Tasks:**
- Handle Enter key for line splitting
- Handle line deletion (dd command)
- Handle line joining
- Update cursor position after line operations
- Maintain proper line endings

**Technical Details:**
```zig
fn insertLine(data: [*]u8, file_size: usize, editor_state: *EditorState) void {
    // Insert '\n' at cursor position
    // Shift all subsequent bytes right
    // Update cursor to start of new line
}
```

### Phase 10: Search Functionality

**Goal:** Add search and replace capabilities

**Tasks:**
- Handle '/' key to enter search mode
- Parse search pattern
- Highlight matches in file
- Navigate to next/previous match
- Optional replace functionality (:s/pattern/replace/)

**Technical Details:**
```zig
fn searchPattern(data: [*]const u8, size: usize, pattern: []const u8) ?usize {
    // Simple string search
    // Return byte offset of first match
}
```

### Future Advanced Features

#### File Size Handling (mremap)
- Grow files when insertion exceeds allocated space
- Shrink files when content is deleted
- Use `mremap` syscall (25) for resizing

#### Undo/Redo System
- Store operation history in memory
- Reverse operations for undo
- Replay operations for redo
- Memory-efficient storage

#### Syntax Highlighting
- Simple keyword-based highlighting
- ANSI color codes for different token types
- Configurable color schemes

#### Multiple Buffers
- Support opening multiple files
- Buffer switching (:bnext, :bprev)
- Buffer management

#### Advanced Navigation
- Page up/down (Ctrl+B, Ctrl+F)
- Goto line (:line_number)
- Jump to percentage in file

---

## Phase 4 Implementation Notes

### msync Syscall (Number 26)

```zig
const Syscall = enum(usize) {
    write = 1, exit = 60, read = 0, open = 2, close = 3,
    fstat = 5, mmap = 9, munmap = 11, msync = 26
};
```

Linux x86_64 syscall 26 is `msync` for synchronizing memory-mapped files.

### Save Function Implementation

```zig
fn saveFile(data: [*]u8, aligned_size: usize, modified: bool) bool {
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
```

### MAP_SHARED vs MAP_PRIVATE

| Flag | Behavior |
|------|----------|
| MAP_SHARED | Changes written back to file; visible to other processes |
| MAP_PRIVATE | Copy-on-write; changes not persisted |

**Critical:** `msync` only works with `MAP_SHARED` mappings. With `MAP_PRIVATE`, modifications never reach the underlying file.

### Command Mode

Simple command sequence for saving:
1. Press `:` to enter command mode
2. Press `w` to trigger save
3. File is synced via `msync(MS_SYNC)`

```zig
if (buffer[0] == ':') {
    in_command = true;
} else if (in_command and buffer[0] == 'w') {
    _ = saveFile(data, aligned_size, true);
    in_command = false;
}
```

### Binary Size Growth

- Phase 1: 1.2KB (freestanding entry)
- Phase 2: 1.6KB (+400 bytes for mmap/fstat support)
- Phase 5: 1.7KB (+100 bytes for argv parsing)
- Phase 4: 1.7KB (+minimal for msync/wrapper)

Still well under 600KB target (99.7% under budget).

---

## Common Issues and Solutions

### mmap Returns Null

If `rawMmap()` returns `null`, check:
- File was opened with correct permissions (O_RDWR for read/write)
- File size is non-zero (empty files need special handling)
- Length is page-aligned (use `alignUp(size, PAGE_SIZE)`)
- Protection flags match open flags (PROT_READ requires O_RDONLY or O_RDWR)

### Stat Buffer Size

The `stat` structure size varies by architecture:
- x86_64 Linux: 144 bytes
- i386 Linux: 64 bytes

Always use buffer large enough for target platform.

### Syscall Register Clobbering

The `syscall` instruction clobbers RCX and R11. Do not use these for passing arguments to syscalls. Use R10 for the 4th argument instead.

### Unused Variable Warnings

Zig requires all non-void values to be used:

```zig
// Error: value of type 'isize' ignored
rawClose(fd);

// Fix: Explicitly discard
const result = rawClose(fd);
_ = result;
```

---

## Current Project Status

- **Binary Size:** ~19K (19,456 bytes)
- **Target:** < 600KB ✓ (97% under budget)
- **Source Lines:** 1,440 lines
- **Status:** Phase 13+ LSP Ready - Full editor with LSP architecture
- **Features Implemented:**
  - [x] Freestanding entry (no LibC)
  - [x] Raw syscalls (write, read, exit, fork, execve, pipe)
  - [x] mmap for zero-copy file access
  - [x] fstat for file size detection
  - [x] Viewport rendering (20 lines)
  - [x] j/k scroll navigation
  - [x] Command-line argument parsing (argc/argv from stack)
  - [x] Memory cleanup on exit (munmap)
  - [x] Input validation (read_result checks)
  - [x] File saving (msync syscall)
  - [x] ANSI diff rendering (double-buffering)
  - [x] Character insertion (insert mode)
  - [x] Undo/Redo system (Ctrl+Z)
  - [x] Delete/Backspace Support
  - [x] Cursor Movement (arrows, h/j/k/l, Home/End)
  - [x] Line Operations (Enter split, dd delete, J join)
  - [x] Search Functionality (/pattern, n/N navigation)
  - [x] File Size Handling (mremap, ftruncate)
  - [x] Status Bar Enhancements (mode, line, col, size, modified)
  - [x] LSP Client Architecture (ready for language servers)
- **Next Phases:**
  - Phase 15: Multiple Buffers
  - Phase 16: Additional Navigation
  - Phase 17: Configuration System
  - Phase 18: Mouse Support

---

*Last Updated: 2026-01-12*

---

## Phase 8-13 Implementation Notes

### Phase 8: Delete/Backspace Support

**Added Functions:**
- `deleteChar()` - Deletes character at cursor or before cursor (backspace)
- Supports both ASCII backspace (8) and Delete key escape sequence (`\x1b[3~`)
- Records delete operations in undo buffer

**Key Implementation:**
```zig
fn deleteChar(data: [*]u8, file_size: usize, editor_state: *EditorState, backspace: bool) void {
    // Find byte offset at cursor
    // Shift bytes left to remove character
    // Record operation for undo
    recordOperation(editor_state, .{ .op_type = .delete, .position = byte_offset, .char = deleted_char });
}
```

**Escape Sequence Handling:**
```zig
// Delete key: \x1b[3~
if (read_more2 > 0 and buffer[2] == '3') {
    const read_more3 = rawRead(STDIN_FILENO, raw_buffer[3..].ptr, 1);
    if (read_more3 > 0 and raw_buffer[3] == '~') {
        deleteChar(data, file_size, &editor_state, false);
    }
}
```

**Bug Found and Fixed:**
- `undoOperation()` had incorrect byte shifting for insert undo: `data[i] = data[i - 1]` should be `data[i] = data[i + 1]`

---

### Phase 9: Cursor Movement

**Added Functions:**
- `getLineLength()` - Get length of a specific line
- `getTotalLines()` - Get total line count
- `moveCursor()` - Move cursor in 6 directions (up, down, left, right, home, end)
- `ensureCursorVisible()` - Auto-scroll when cursor moves outside viewport

**New EditorState Fields:**
```zig
line_offset: usize = 0,  // Current scroll offset
```

**Escape Sequences for Keys:**
| Key | Sequence | Direction |
|-----|----------|-----------|
| Up Arrow | `\x1b[A` | .up |
| Down Arrow | `\x1b[B` | .down |
| Right Arrow | `\x1b[C` | .right |
| Left Arrow | `\x1b[D` | .left |
| Home | `\x1b[H` | .home |
| End | `\x1b[F` | .end |
| Delete | `\x1b[3~` | N/A |

**Vim-style Movement:**
| Key | Action |
|-----|--------|
| h | Move left |
| j | Scroll down (or move down if in line) |
| k | Scroll up (or move up if in line) |
| l | Move right |
| 0 | Home (line start) |
| $ | End (line end) |

**Important:** Arrow keys require reading multiple bytes (escape sequence parsing).

---

### Phase 10: Line Operations

**Added Functions:**
- `splitLine()` - Enter key inserts newline at cursor, moves cursor to new line
- `deleteLine()` - `dd` command deletes entire current line
- `joinLine()` - `J` command joins current line with next line

**Multi-key Command Handling:**
```zig
if (raw_buffer[0] == 'd') {
    const read_result2 = rawRead(STDIN_FILENO, &normal_mode_buffer, 1);
    if (read_result2 > 0 and normal_mode_buffer[0] == 'd') {
        deleteLine(data, file_size, &editor_state);
    }
}
```

**Key Issue:** Multi-key commands require reading ahead without blocking. Solution: read second key immediately after first.

---

### Phase 11: Search Functionality

**Added to EditorState:**
```zig
search_mode: bool = false,
search_buffer: [256]u8 = undefined,
search_len: usize = 0,
search_match_row: usize = 0,
search_match_col: usize = 0,
search_match_offset: usize = 0,
```

**Added Functions:**
- `searchForward()` - Simple forward string search
- `searchBackward()` - Simple backward string search
- `offsetToRowCol()` - Convert byte offset to (row, col) position
- `executeSearch()` - Execute forward search with wrapping
- `executeSearchBackward()` - Execute backward search with wrapping

**Search Mode:**
| Key | Action |
|-----|--------|
| / | Enter search mode |
| ESC | Cancel search |
| Enter | Execute search |
| n | Next match |
| N | Previous match |
| Backspace | Delete search character |
| Any char | Add to search pattern |

**Current Limitation:** Search is simple substring match, no regex support.

---

### Phase 12: File Size Handling

**Added Syscalls:**
```zig
const Syscall = enum(usize) { 
    write = 1, exit = 60, read = 0, open = 2, close = 3, 
    fstat = 5, mmap = 9, munmap = 11, msync = 26, 
    mremap = 25, ftruncate = 77  // New syscalls
};
```

**Added Functions:**
```zig
fn rawMremap(old_addr: [*]u8, old_size: usize, new_size: usize, flags: usize) ?[*]u8
fn rawFtruncate(fd: usize, length: usize) isize
```

**Syscall5 for mremap:**
```zig
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
```

---

### Phase 13: Status Bar Enhancements

**Enhanced Status Bar (row 0):**
```
[NORMAL] 1,1 | 1024 [MODIFIED]
```

**Shows:**
- Mode indicator (NORMAL/INSERT/SEARCH)
- Line number (1-based)
- Column number (1-based)
- File size in bytes
- Modified indicator

**Rendering Numbers:**
```zig
// Convert number to string
var n = line_num;
var digits: [16]u8 = undefined;
var digit_count: usize = 0;
while (n > 0) : (n /= 10) {
    digits[digit_count] = '0' + @as(u8, @intCast(n % 10));
    digit_count += 1;
}
// Reverse digits
```

---

## Errors Encountered and Solutions

### Error: "unused local variable"
**Cause:** Variables declared but not used
**Solution:** Use `const` for read-only values or prefix with `_` to indicate intentional unused:
```zig
const _size = ...;  // Intentionally unused parameter
```

### Error: "use of undeclared identifier"
**Cause:** Variable name mismatch between declaration and usage
**Solution:** Ensure consistent naming. In one case, renamed `line_offset` parameter to use `editor_state.line_offset` to avoid confusion.

### Error: "redeclaration of local variable"
**Cause:** Using `var n` twice in the same scope
**Solution:** Use unique variable names or reuse the same variable:
```zig
var n = line_num;
// ... use n ...
n = col_num;  // Reuse same variable
```

### Error: "expected expression, found '}'"
**Cause:** Corrupted code during editing (broken paste)
**Solution:** Carefully re-read the code and fix the syntax.

### Error: "unused function parameter"
**Cause:** Parameter declared but not used in function body
**Solution:** Use `_ = parameter;` to acknowledge or use the parameter:
```zig
fn searchBackward(data: [*]const u8, file_size: usize, ...) ?usize {
    _ = file_size;  // Acknowledge parameter
    // ...
}
```

### Error: Pointer Type Mismatch
**Cause:** `rawRead` expects `[*]u8` but `&buffer[1]` returns `*u8`
**Solution:** Use slice syntax:
```zig
rawRead(STDIN_FILENO, raw_buffer[1..].ptr, 1)
```

---

## Binary Size Evolution

| Phase | Feature | Size | Change |
|-------|---------|------|--------|
| 1 | Freestanding Entry | 1.2KB | - |
| 2 | mmap I/O | 1.6KB | +400B |
| 5 | CLI Arguments | 1.7KB | +100B |
| 6 | Insert Mode | 2.0KB | +300B |
| 7 | Undo/Redo | 11KB | +9KB |
| 8 | Delete/Backspace | 12KB | +1KB |
| 9 | Cursor Movement | 13KB | +1KB |
| 10 | Line Operations | 14KB | +1KB |
| 11 | Search | 15KB | +1KB |
| 12 | File Size (syscalls) | 15KB | +0KB |
| 13 | Status Bar | 15KB | +0KB |

**Total:** 15KB (98% under 600KB budget)

---

## Key Implementation Patterns

### 1. Escape Sequence Handling
```zig
// Read first byte
const read_result = rawRead(STDIN_FILENO, &buffer, 1);

// Check for escape (0x1b)
if (buffer[0] == 0x1b) {
    // Read next byte
    const read_more = rawRead(STDIN_FILENO, buffer[1..].ptr, 1);
    if (read_more > 0 and buffer[1] == '[') {
        // Read third byte
        const read_more2 = rawRead(STDIN_FILENO, buffer[2..].ptr, 1);
        // Handle based on third byte
    }
}
```

### 2. Multi-key Command Handling
```zig
if (raw_buffer[0] == 'd') {
    const read_result2 = rawRead(STDIN_FILENO, &normal_mode_buffer, 1);
    if (read_result2 > 0 and normal_mode_buffer[0] == 'd') {
        // Execute dd command
    }
}
```

### 3. Mode-based Input Handling
```zig
if (editor_state.insert_mode) {
    // Handle insert mode input
} else if (editor_state.search_mode) {
    // Handle search mode input
} else {
    // Handle normal mode input
}
```

### 4. Number to String Conversion
```zig
var n = number;
var digits: [16]u8 = undefined;
var digit_count: usize = 0;
while (n > 0) : (n /= 10) {
    digits[digit_count] = '0' + @as(u8, @intCast(n % 10));
    digit_count += 1;
}
// digits contains reversed number, print in reverse order
```

---

## LSP Client Integration (Phase 14+)

### Reference Implementation: zigjr Library

**GitHub:** https://github.com/williamw520/zigjr
**License:** MIT
**Stars:** 47+

zigjr is a lightweight Zig library providing full JSON-RPC 2.0 protocol implementation. We studied its `lsp_client.zig` example to understand LSP client patterns.

**Key Features of zigjr:**
- Parsing and composing JSON-RPC 2.0 messages
- Support for Request, Response, Notification, and Error messages
- Message streaming via Content-Length header-based streams
- RPC pipeline for request-to-response lifecycle
- **Example LSP client showing process spawning and communication**

### LSP Architecture in Spectre-IDE

**Reference:** zigjr/examples/lsp_client.zig

The LSP client follows patterns from zigjr's implementation:

```zig
// Process spawning pattern (from zigjr)
var child = std.process.Child.init(args.cmd_argv.items, alloc);
child.stdin_behavior    = .Pipe;
child.stdout_behavior   = .Pipe;
try child.spawn();

// LSP message pattern
try writeContentLengthRequest(alloc, in_writer, "initialize", initializeParams, RpcId.of(id));
```

**LSP Message Flow (from zigjr example):**
1. Spawn LSP server process with piped stdin/stdout
2. Send `initialize` request → Wait for response
3. Send `initialized` notification
4. Send `textDocument/didOpen` with file content
5. Request features: `textDocument/semanticTokens/full`, `textDocument/hover`, `textDocument/definition`
6. Send `shutdown` → `exit` → Close pipes

**Integration Points:**
1. **Manual LSP Activation**: User runs `:lsp <server>` command
2. **File Open**: Send initialize → Send didOpen → Request semantic tokens
3. **File Edit**: Send didChange notifications → Request updated tokens
4. **Syntax Highlighting**: Apply ANSI colors based on semantic token types
5. **File Close**: Send didClose → Stop server

### LSP Message Framing (JSON-RPC 2.0)

**Format (LSP Standard):**
```
Content-Length: 123\r\n
\r\n
{"jsonrpc": "2.0", "id": 1, "method": "...", "params": {...}}
```

**Key Components:**
- `Content-Length: <bytes>` - Exact byte count of JSON body (required)
- Blank line (`\r\n`) - Separates header from body
- JSON-RPC 2.0 message - Valid JSON with `"jsonrpc": "2.0"`

**Message Types:**
- **Request:** `{"jsonrpc": "2.0", "id": 1, "method": "...", "params": {...}}`
- **Notification:** `{"jsonrpc": "2.0", "method": "...", "params": {...}}` (no id)
- **Response:** `{"jsonrpc": "2.0", "id": 1, "result": {...}}`
- **Error:** `{"jsonrpc": "2.0", "id": 1, "error": {"code": ..., "message": "..."}}`

### Semantic Token Types

LSP semantic tokens provide language-aware highlighting:

| Token Type | ANSI Color | Description |
|------------|------------|-------------|
| `keyword` | Yellow (33) | Language keywords (if, while, fn) |
| `string` | Green (32) | String literals |
| `number` | Cyan (36) | Numeric literals |
| `comment` | Gray (90) | Comments |
| `function` | Blue (34) | Function names |
| `type` | Magenta (35) | Type names |
| `variable` | Red (31) | Variable names |
| `parameter` | Gray (37) | Function parameters |

### LSP Servers Supported

| Language | Server | Install Command |
|----------|--------|-----------------|
| Zig | zls | `zig fetch --save https://github.com/zigtools/zls/archive/refs/tags/<version>.tar.gz` |
| C/C++ | clangd | `sudo apt install clangd` |
| Python | pyls/pylsp | `pip install python-lsp-server` |
| Rust | rust-analyzer | `rustup add rust-analyzer` |
| Go | gopls | `go install golang.org/x/tools/gopls@latest` |

### Implementation Strategy

**Based on zigjr patterns, we implement in pure Zig (no dependencies):**

1. **syscalls.zig** - Add process/pipe syscalls:
   - `rawFork()` - Clone process
   - `rawExecve()` - Execute LSP server
   - `rawPipe()` - Create communication pipes
   - `rawDup2()` - Redirect file descriptors
   - `rawWaitpid()` - Wait for child process
   - `rawRead()` / `rawWrite()` - Pipe I/O

2. **json.zig** - Minimal JSON builder:
   - `buildRequest()` - Create JSON-RPC requests
   - `buildNotification()` - Create notifications
   - `parseContentLength()` - Extract header value
   - `findJsonStart()` - Locate JSON body start

3. **lsp_client.zig** - LSP client implementation:
   - `startServer()` - Spawn LSP process
   - `sendInitialize()` - Send initialize request
   - `sendDidOpen()` - Open document
   - `requestSemanticTokens()` - Get highlights
   - `readMessage()` - Parse responses
   - `sendShutdown()` / `sendExit()` - Clean shutdown

4. **main.zig** - Integration:
   - Detect language from file extension
   - Start appropriate LSP server
   - Render semantic tokens with ANSI colors
   - Handle LSP diagnostics (errors/warnings)

### Reference Code Patterns

**From zigjr lsp_client.zig - Request Worker Pattern:**
```zig
fn request_worker(in_stdin: std.fs.File) !void {
    std.Thread.sleep(1_000_000_000);  // Wait for server
    try writeContentLengthRequest(alloc, in_writer, "initialize", initializeParams, RpcId.of(id));
    try writeContentLengthRequest(alloc, in_writer, "textDocument/didOpen", didOpenParams, RpcId.ofNone());
    try writeContentLengthRequest(alloc, in_writer, "textDocument/semanticTokens/full", semParams, RpcId.of(id));
}
```

**From zigjr lsp_client.zig - LSP Message Structures:**
```zig
const InitializeParams = struct {
    processId: ?i32 = null,
    rootUri: ?[]const u8 = null,
    capabilities: ClientCapabilities,
};

const TextDocumentItem = struct {
    uri: []const u8,
    languageId: []const u8,
    version: i32,
    text: []const u8,
};

const SemanticTokensParams = struct {
    textDocument: TextDocumentIdentifier,
};
```

### Size Impact

| Component | Estimated Size |
|-----------|---------------|
| syscalls.zig (process/pipe) | +800B |
| json.zig (minimal parser) | +600B |
| lsp_client.zig | +2KB |
| Integration in main.zig | +400B |
| **Total LSP Client** | **~4KB** |

**Final binary:** ~164KB (73% under 600KB budget)

### LSP Capabilities We Implement

| Feature | Method | Priority |
|---------|--------|----------|
| Syntax Highlighting | textDocument/semanticTokens/full | High |
| Diagnostics | textDocument/publishDiagnostics | High |
| Hover Info | textDocument/hover | Medium |
| Definition | textDocument/definition | Medium |
| Completion | textDocument/completion | Low |
| References | textDocument/references | Low |

### What LSP Cannot Do

**Limitations:**
- Cannot run shell commands
- Cannot access files outside project root (sandboxed)
- Cannot directly edit files (only suggests changes)
- Cannot handle UI/rendering (editor responsibility)

**Our editor handles:**
- Process spawning and management
- ANSI color rendering
- User interaction and navigation

### Manual LSP Server Selection

LSP servers are activated manually for clarity and control:

**Command Format:**
```
:lsp <server_name>
```

**Available Servers:**
| Server | Language | Notes |
|--------|----------|-------|
| `zls` | Zig | Zig Language Server |
| `clangd` | C/C++ | LLVM Clang Language Server |
| `pylsp` | Python | Python LSP Server |
| `rust-analyzer` | Rust | Rust Language Server |
| `gopls` | Go | Go Language Server |
| `none` | - | Disable LSP |

**Usage Examples:**
```
:lsp clangd     // Enable C/C++ syntax highlighting
:lsp zls        // Enable Zig syntax highlighting  
:lsp none       // Disable LSP
```

**Why Manual Selection?**
- Avoids ambiguous automatic detection (e.g., .h files could be C or C++)
- Gives users explicit control over LSP server choice
- Simpler code without complex file type heuristics
- Works consistently across different environments

### Resources

- **LSP Specification:** https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
- **zigjr Library:** https://github.com/williamw520/zigjr
- **LSP Implementations:** https://microsoft.github.io/language-server-protocol/implementors/servers/
- **zigjr LSP Client Example:** https://github.com/williamw520/zigjr/blob/master/examples/lsp_client.zig

---

## Advanced Navigation (Phase 16)

### Features Implemented

**Page Navigation:**
- Page Up: `Ctrl+B` or `PgUp` key
- Page Down: `Ctrl+F` or `PgDn` key
- Scrolls one viewport height at a time

**Line Jumping:**
- `:123` - Jump to line 123 (1-based)
- `gg` - Go to beginning of file (line 1)
- `G` - Go to end of file

**Word Navigation:**
- `w` - Move to start of next word
- `b` - Move to start of previous word
- `e` - Move to end of current word

**Word Definition:**
```
fn isWordChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
           (c >= 'A' and c <= 'Z') or
           (c >= '0' and c <= '9') or
           c == '_';
}
```

**Cursor Movement:**
| Key | Action |
|-----|--------|
| `h` / `←` | Move left |
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `l` / `→` | Move right |
| `0` | Move to line beginning |
| `$` | Move to line end |

---

## Configuration System (Phase 17)

### Configuration Structure

```zig
const Config = struct {
    tab_size: usize = 4,
    syntax_highlighting: bool = false,
    auto_lsp: bool = false,
    lsp_server: [32]u8,
    status_line: bool = true,
    line_numbers: bool = false,
    auto_indent: bool = true,
    wrap_lines: bool = false,
};
```

### Commands

**`:set` - Display all options**
```
:set
```

**`:set <option>=<value>` - Set option**
```
:tabsize=4
:syntaxhighlighting=true
:autolsp=false
```

### Configuration File

**Location:** `~/.spectreiderc` (future)

**Format:**
```ini
tabsize=4
syntaxhighlighting=false
autolsp=false
statusline=true
linenumbers=false
autoindent=true
wraplines=false
```

---

## Remaining Phases (18)

| Phase | Feature | Est. Size | Status |
|-------|---------|-----------|--------|
| 14 | LSP Syntax Highlighting | +4KB | ✅ Complete |
| 15 | Multiple Buffers | +1KB | ✅ Complete |
| 16 | Additional Navigation | +300B | ✅ Complete |
| 17 | Configuration System | +400B | ✅ Complete |
| 18 | Mouse Support | +500B | ⏳ Pending |

**Final Target:** ~170KB (72% under budget)

*Last Updated: 2026-01-12*
