# Spectre-IDE

A minimalist freestanding text editor built with Zig, targeting binary size under 600KB with zero-copy memory-mapped I/O architecture.

## Project Status

**Phase 7 Complete** - Full-featured editor with undo/redo

- **Binary Size:** 11KB (Target: <600KB) - Prebuilt binary available
- **RAM Usage:** Minimal (uses OS paging for large files)
- **Architecture:** Zero-copy via mmap
- **Platform:** Linux x86_64 freestanding (no LibC)

## Features

- [x] Freestanding mode (no LibC dependency)
- [x] Direct Linux syscalls via inline assembly
- [x] Memory-mapped file I/O (zero-copy)
- [x] Zero-Copy architecture for files larger than physical RAM
- [x] Viewport rendering with efficient delta updates
- [x] Scroll navigation (j/k keys)
- [x] File saving with msync ( :w command)
- [x] Command-line argument parsing
- [x] Character insertion mode (i key)
- [x] Undo/Redo system (Ctrl+Z)
- [x] Prebuilt binary (no Zig installation required)

## Building

```bash
# Install Zig 0.16-dev (required)
# Build release binary
/opt/zig/zig build -Drelease=true

# Binary output
ls -lh zig-out/bin/spectre-ide
```

## Usage

### Quick Start (Linux x86_64)

```bash
# Use pre-built binary (no Zig installation needed!)
./bin/spectre-ide your_file.txt

# Controls:
#   j/k - scroll up/down
#   i - enter insert mode (type to edit)
#   ESC - exit insert mode
#   Ctrl+Z - undo last edit
#   :w - save file
#   q - exit
```

### Build from Source

```bash
/opt/zig/zig build -Drelease=true
./zig-out/bin/spectre-ide
```

## Architecture

### Zero-Copy Memory Mapping

Unlike traditional editors that load entire files into RAM, Spectre-IDE uses `mmap()` to map files directly into virtual memory. This allows:

- **No RAM limit:** Edit files larger than physical memory (OS paging handles it)
- **No buffer copying:** File data accessed directly at virtual addresses
- **Automatic write-back:** Modified pages written to disk by OS (with MAP_SHARED)

### Freestanding Mode

The editor is compiled for freestanding targets, meaning:

- No standard library (LibC)
- All syscalls via inline assembly
- Binary size optimization (<600KB target)
- Manual memory management (no heap allocator)

## Development

### Project Structure

```
src/main.zig    - Main editor implementation
build.zig       - Zig build system configuration
ZIG.md          - Comprehensive Zig reference guide
```

### Syscalls Used

- `write` (1) - Terminal output
- `read` (0) - Input handling
- `exit` (60) - Program termination
- `open` (2) - File opening
- `close` (3) - File closing
- `fstat` (5) - File size detection
- `mmap` (9) - Memory mapping
- `munmap` (11) - Memory unmapping
- `msync` (26) - File synchronization

## Documentation

See [ZIG.md](ZIG.md) for comprehensive documentation on:
- Freestanding mode configuration
- Inline assembly patterns
- Syscall wrapper implementation
- Memory-mapped I/O usage
- Build system configuration
- Common issues and solutions

## Progress

- **Phase 1:** Freestanding entry and raw syscalls ✓
- **Phase 2:** Memory-mapped I/O and viewport rendering ✓
- **Phase 3:** ANSI diff rendering ✓
- **Phase 4:** File saving with msync ✓
- **Phase 5:** Command-line argument parsing ✓
- **Phase 6:** Character insertion (edit mode) ✓
- **Phase 7:** Undo/Redo system ✓

**Future Phases:**
- Phase 8: Delete/Backspace support
- Phase 9: Cursor movement
- Phase 10: Line operations

## License

MIT

## About

Built with Zig 0.16.0-dev targeting x86_64 Linux freestanding mode.
