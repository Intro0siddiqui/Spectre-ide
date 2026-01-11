# Spectre-IDE Roadmap

## Overview

Spectre-IDE is a minimalist freestanding text editor built with Zig, targeting binary size under 600KB with zero-copy memory-mapped I/O architecture.

**Goal:** Surpass vi by enabling editing of files larger than physical RAM through OS paging.

---

## Current Status

### Phase 2: Memory-Mapped I/O ✅ COMPLETE
- [x] mmap syscall wrapper (6 arguments)
- [x] fstat syscall for file size
- [x] Viewport rendering (20 lines)
- [x] j/k scroll navigation
- [x] Zero-copy architecture
- **Binary:** 1.6KB (target: <600KB)
- **Status:** Working, file loading and scrolling functional

### Bug Fixes (In Progress)
- [x] Segfault on exit - added read_result check
- [x] Memory leak - added rawMunmap before exit
- [x] Shadow variable error - fixed aligned_size reuse

---

## Roadmap

### Phase 5: Command-Line Argument Parsing 🚧 IN PROGRESS

**Goal:** Accept filename as argument instead of hardcoded path

**Tasks:**
- [x] Add `parseArgcArgv()` function to read argc/argv from stack
- [x] Parse stack pointer to get argc at current location
- [x] Get argv array pointer (sp + sizeof(usize))
- [x] Use default file `/tmp/test_file.txt` if no argument provided
- [ ] Test with actual filename: `./spectre-ide file.txt`
- [ ] Update usage message in README.md
- [ ] Error handling for non-existent files

**Technical Details:**
```zig
fn parseArgcArgv() struct { argc: usize, argv: [*][*]u8 } {
    var sp: usize = 0;
    asm volatile ("mov %%rsp, %[sp]" : [sp] "=r" (sp));
    const argc = @as(*const usize, @ptrFromInt(sp)).*;
    const argv = @as([*][*]u8, @ptrFromInt(sp + @sizeOf(usize)));
    return .{ .argc = argc, .argv = argv };
}
```

**Completion Criteria:**
- `./spectre-ide` uses default file
- `./spectre-ide my_file.txt` loads specified file
- Error messages display for missing files
- README.md updated with usage examples

---

### Phase 4: File Saving ⏳ NEXT

**Goal:** Persist edits back to disk with proper dirty page tracking

**Tasks:**
- [ ] Add `msync` syscall wrapper (syscall number 26)
- [ ] Implement dirty page tracking
  - Track modified byte ranges
  - Mark pages as dirty when modified
- [ ] Add save command `:w`
  - Parse ':' commands in input loop
  - Trigger msync on dirty pages
  - Display save confirmation
- [ ] Add `msync` constants
  - `MS_ASYNC = 1`
  - `MS_SYNC = 4`
  - `MS_INVALIDATE = 2`
- [ ] Error handling for save failures

**Technical Details:**
```zig
const MS_SYNC: usize = 4;
const MS_ASYNC: usize = 1;

fn rawMsync(addr: [*]const u8, length: usize, flags: usize) isize {
    return @bitCast(syscall3(@as(Syscall, @enumFromInt(26)), @intFromPtr(addr), length, flags));
}
```

**Completion Criteria:**
- Typing `:w` saves changes to disk
- Only dirty pages are synced
- Confirmation message displayed
- Errors handled gracefully
- File size changes handled (if growing/shrinking)

**Advanced (Future):**
- Auto-save on dirty page threshold
- File size modification (grow/shrink with mremap)
- Backup file creation

---

### Phase 3: ANSI Diff Rendering ⏳ OPTIMIZATION

**Goal:** Minimize redraws by only updating changed screen cells

**Tasks:**
- [ ] Implement double-buffering
  - Previous screen content buffer
  - Current screen content buffer
  - Compare before rendering
- [ ] Calculate delta between frames
  - Line-by-line comparison
  - Character-by-character comparison within lines
- [ ] Optimize ANSI codes
  - Only send cursor moves for changed positions
  - Only send changed characters
  - Skip unchanged lines/regions
- [ ] Benchmark performance improvement
  - Measure syscalls per frame
  - Compare with full redraw

**Technical Details:**
```zig
const ScreenBuffer = struct {
    previous: [MAX_ROWS][MAX_COLS]u8,
    current: [MAX_ROWS][MAX_COLS]u8,
    
    fn renderDiff(self: *ScreenBuffer) void {
        // Compare buffers and only send ANSI codes for differences
    }
};
```

**Completion Criteria:**
- Only changed cells updated
- Minimized cursor movement sequences
- 50%+ reduction in syscall count
- Performance benchmarked

**Advanced (Future):**
- Partial line updates
- Cursor position optimization
- Batched character writes

---

## Future Features

### Editing Operations
- [ ] Insert mode triggered by `i` key
- [ ] Delete mode
- [ ] Backspace/delete support
- [ ] Character insertion at cursor
- [ ] Line splitting/merging

### Navigation Enhancements
- [ ] Line numbers display
- [ ] Jump to line number
- [ ] Search functionality (`/pattern`)
- [ ] Page up/down (Ctrl+B/Ctrl+F)

### File Operations
- [ ] Multiple file support (buffers)
- [ ] Switch between files
- [ ] File browser
- [ ] Recent files list

### Advanced mmap Features
- [ ] `mremap` for resizing files in place
- [ ] Sparse file support
- [ ] Memory-mapped file creation

### Syntax Highlighting
- [ ] Simple keyword highlighting
- [ ] Configurable color schemes
- [ ] Language detection

### Status Bar
- [ ] Current line/column
- [ ] File name
- [ ] Modified indicator (*)
- [ ] Position percentage

---

## Performance Targets

| Metric | Target | Current |
|--------|--------|---------|
| Binary Size | < 600KB | 1.6KB ✅ |
| Idle RAM | < 400KB | TBD |
| Large File Support | > physical RAM | ✅ (mmap) |
| Startup Time | < 100ms | TBD |
| Scroll Latency | < 16ms (60fps) | TBD |
| Syscalls/frame | < 50 (with Phase 3) | TBD |

---

## Technical Constraints

- **Platform:** Linux x86_64 freestanding
- **Compiler:** Zig 0.16.0-dev
- **Dependencies:** None (no LibC)
- **Architecture:** Zero-copy via mmap
- **Binary Size:** < 600KB
- **RAM Usage:** < 400KB idle

---

## Priority Order

1. **High Priority:** Bug fixes (segfault, memory leaks)
2. **High Priority:** Phase 5 - Command-line parsing (core usability)
3. **Medium Priority:** Phase 4 - File saving (basic completeness)
4. **Low Priority:** Phase 3 - ANSI diff (optimization - nice to have)
5. **Future:** Editing operations, navigation, advanced features

---

## Known Limitations

- No undo/redo (complex for freestanding)
- No copy/paste (requires clipboard access)
- No mouse support (terminal only)
- No syntax highlighting (planned)
- No split windows (memory constraints)
- No plugins/modular architecture (binary size target)

---

## Contributing

This is a minimal project focused on architectural innovation. PRs should:
- Maintain freestanding mode (no LibC)
- Keep binary size under 600KB
- Follow zero-copy mmap architecture
- Use direct syscalls only
- Document any new syscalls in ZIG.md

---

*Last Updated: 2026-01-11*
*Phase 2 Complete | Phase 5 In Progress*
