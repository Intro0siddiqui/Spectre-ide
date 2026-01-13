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
zig build
./zig-out/bin/spectre-ide <filename>
```

For development/debug build with symbols:
```bash
zig build -Doptimize=Debug
./zig-out/bin/spectre-ide <filename>
```

## Usage

```bash
./zig-out/bin/spectre-ide your_file.txt
```

### Key Bindings


## Requirements

- Linux x86_64
- Zig 0.15.2

## License

MIT

---

Built with Zig targeting x86_64 Linux freestanding mode.
