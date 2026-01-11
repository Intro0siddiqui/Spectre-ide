# Spectre-IDE

A minimalist freestanding text editor built with Zig, targeting binary size under 600KB with zero-copy memory-mapped I/O architecture.

## Project Status

**Phase 2 Complete** - Memory-mapped file editing implemented

- **Binary Size:** 1.6KB (Target: <600KB)
- **RAM Usage:** Minimal (uses OS paging for large files)
- **Architecture:** Zero-copy via mmap
- **Platform:** Linux x86_64 freestanding (no LibC)

## Features

- [x] Freestanding mode (no LibC dependency)
- [x] Direct Linux syscalls via inline assembly
- [x] Memory-mapped file I/O (zero-copy)
- [x] Zero-Copy architecture for files larger than physical RAM
- [x] Viewport rendering
- [x] Scroll navigation (j/k)
- [ ] ANSI diff rendering (Phase 3)
- [ ] File saving with dirty pages (Phase 4)
- [ ] Command-line argument parsing (Phase 5)

## Building

```bash
# Install Zig 0.16-dev (required)
# Build release binary
/opt/zig/zig build -Drelease=true

# Binary output
ls -lh zig-out/bin/spectre-ide
```

## Usage

```bash
# Run editor (currently hardcoded to /tmp/test_file.txt)
./zig-out/bin/spectre-ide

# Controls:
#   j - scroll down
#   k - scroll up
#   q - exit
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
- **Phase 3:** ANSI diff rendering (next)
- **Phase 4:** File saving
- **Phase 5:** Command-line parsing

## License

MIT

## About

Built with Zig 0.16.0-dev targeting x86_64 Linux freestanding mode.
