# Zig Reference Guide for Spectre-IDE Project

**Version:** Zig 0.16.0-dev.2145+ec25b1384  
**Date:** 2026-01-11  
**Project:** Spectre-IDE (Freestanding Editor)  
**Phase:** Phase 2 - Memory-Mapped I/O Complete

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
12. [Common Issues and Solutions](#common-issues-and-solutions)
13. [Current Project Status](#current-project-status)

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

- Phase 1: 1.2KB
- Phase 2: 1.6KB (+400 bytes for mmap/fstat support)

Still well under 600KB target.

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

- **Binary Size:** ~1.6K (1636 bytes)
- **Target:** < 600KB ✓
- **Source Lines:** 247 lines
- **Status:** Phase 2 Complete - Memory-mapped I/O working
- **Features Implemented:**
  - [x] Freestanding entry (no LibC)
  - [x] Raw syscalls (write, read, exit)
  - [x] mmap for zero-copy file access
  - [x] fstat for file size detection
  - [x] Viewport rendering (20 lines)
  - [x] j/k scroll navigation
- **Next Phases:**
  - Phase 3: ANSI diff rendering (minimize redraws)
  - Phase 4: File saving with dirty pages
  - Phase 5: Command-line argument parsing

---

*Last Updated: 2026-01-11*
