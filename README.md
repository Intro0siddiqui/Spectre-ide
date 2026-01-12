# Spectre-IDE

A minimalist freestanding text editor built with Zig, targeting binary size under 600KB with zero-copy memory-mapped I/O architecture.

## Overview

**Binary Size:** 166KB (72% under 600KB budget)  
**Platform:** Linux x86_64 freestanding (no LibC)  
**Architecture:** Zero-copy via mmap for files larger than physical RAM

## Features

### Core Editing
- Character insertion and deletion (Insert mode)
- Backspace and Delete key support
- Undo/Redo system (Ctrl+Z)
- Line operations: Enter to split, `dd` to delete, `J` to join
- File saving with `msync` for data integrity

### Navigation
- Arrow keys and vim-style movement (`h`/`j`/`k`/`l`)
- Page Up/Down (`Ctrl+B` / `Ctrl+F` or PgUp/PgDn)
- Word navigation (`w` - next, `b` - previous, `e` - end)
- Go to line (`:<number>`, e.g., `:100`)
- Go to file start/end (`gg` / `G`)
- Search with `/pattern`, `n` for next, `N` for previous

### LSP Integration
- Manual LSP server activation (`:lsp <server>`)
- Supported servers: `clangd`, `zls`, `pylsp`, `rust-analyzer`, `gopls`
- Semantic token highlighting (when LSP active)
- Diagnostic display for errors/warnings

### Interface
- Efficient ANSI diff rendering (minimal redraws)
- Status bar showing: mode, line/column, file size, modified status
- Footer help bar with key bindings
- Command mode for extended commands (`:w`, `:lsp`, `:set`, `:<num>`)

### Configuration
- Runtime configuration via `:set` command
- Tab size settings
- LSP server preferences

## Building

```bash
/opt/zig/zig build
./zig-out/bin/spectre-ide <filename>
```

## Usage

```bash
./zig-out/bin/spectre-ide your_file.txt
```

### Key Bindings

| Key | Action |
|-----|--------|
| `i` | Enter insert mode |
| `ESC` | Exit insert mode |
| `Ctrl+Z` | Undo |
| `:w` | Save file |
| `:q` | Quit |
| `/` | Search |
| `n` / `N` | Next/previous search match |
| `h`/`j`/`k`/`l` | Cursor movement |
| `gg` | File start |
| `G` | File end |
| `w` | Next word |
| `b` | Previous word |
| `e` | Word end |
| `PgUp` / `PgDn` | Page scroll |
| `:<num>` | Go to line |
| `:lsp <server>` | Enable LSP (clangd, zls, etc.) |
| `:set` | Show configuration |

## Architecture

### Zero-Copy Memory Mapping

Spectre-IDE uses `mmap()` to map files directly into virtual memory:
- Edit files larger than physical RAM (OS paging handles it)
- No buffer copying - data accessed directly at virtual addresses
- Modified pages written to disk by OS (with MAP_SHARED)

### Freestanding Mode

Compiled for freestanding targets:
- No standard library (LibC)
- All syscalls via inline assembly
- Manual memory management
- Minimal binary footprint

## Project Structure

```
src/main.zig         - Main editor implementation
src/syscalls.zig     - Raw Linux syscalls
src/json.zig         - Minimal JSON builder for LSP
src/lsp_client.zig   - LSP client implementation
src/config.zig       - Configuration system
build.zig            - Zig build system
ZIG.md               - Technical documentation
IMPLEMENTATION_PLAN.md - Feature roadmap
```

## Requirements

- Linux x86_64
- Zig 0.16.0-dev or later

## License

Apache-2.0 

---

Built with Zig targeting x86_64 Linux freestanding mode.
