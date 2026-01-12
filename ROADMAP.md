# Spectre-IDE Roadmap

## Overview

Spectre-IDE is a minimalist freestanding text editor built with Zig, targeting binary size under 600KB with zero-copy memory-mapped I/O architecture.

**Goal:** Surpass vi by enabling editing of files larger than physical RAM through OS paging.

---

## Current Status

### Phase 4: File Saving ✅ COMPLETE
- [x] msync syscall wrapper (syscall number 26)
- [x] MS_ASYNC, MS_SYNC, MS_INVALIDATE constants
- [x] MAP_SHARED for write-back support
- [x] Save command `:w` with command mode
- [x] Error handling for save failures
- **Binary:** 1.7KB (target: <600KB)
- **Status:** Working, file saving functional with msync

### Phase 5: Command-Line Argument Parsing ✅ COMPLETE
- [x] parseArgcArgv() function to read argc/argv from stack
- [x] Parse stack pointer to get argc at current location
- [x] Get argv array pointer (sp + sizeof(usize))
- [x] Use default file `/tmp/test_file.txt` if no argument provided

### Bug Fixes (In Progress)
- [x] Segfault on exit - added read_result check
- [x] Memory leak - added rawMunmap before exit
- [x] Shadow variable error - fixed aligned_size reuse
- [x] Unused function parameter - removed unused size parameter

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

---

### Phase 6: Character Insertion ✅ COMPLETE

**Goal:** Enable basic text editing with insert mode

**Tasks:**
- [x] Add cursor position tracking (row, col) to EditorState
- [x] Add insert mode state to EditorState
- [x] Handle 'i' key to enter insert mode
- [x] Handle character insertion at cursor in insert mode
- [x] Handle ESC key to exit insert mode
- [x] Update viewport rendering to show cursor position
- [x] Simple byte-shifting insertion algorithm

**Technical Details:**
```zig
const EditorState = struct {
    cursor_row: usize = 0,  // Line in file (0-based)
    cursor_col: usize = 0,  // Column in line (0-based)
    insert_mode: bool = false,
    // ... other fields
};

fn insertChar(data: [*]u8, file_size: usize, editor_state: *EditorState, char: u8) void {
    // Find byte offset for cursor position
    // Shift bytes right from insertion point
    // Insert character and update cursor
}
```

**Completion Criteria:**
- [x] Press 'i' to enter insert mode
- [x] Type characters to edit file
- [x] Press ESC to exit insert mode
- [x] Cursor shows position in insert mode
- [x] "(INSERT)" displayed in footer
- [x] Changes marked as modified for saving

---

### Phase 4: File Saving ✅ COMPLETE

**Goal:** Persist edits back to disk with proper dirty page tracking

**Tasks:**
- [x] Add `msync` syscall wrapper (syscall number 26)
- [x] Add `msync` constants
  - `MS_ASYNC = 1`
  - `MS_SYNC = 4`
  - `MS_INVALIDATE = 2`
- [x] Add save command `:w`
  - Parse ':' commands in input loop
  - Trigger msync on dirty pages
  - Display save confirmation
- [x] Error handling for save failures
- [x] MAP_SHARED for write-back support

**Technical Details:**
```zig
const MS_SYNC: usize = 4;
const MS_ASYNC: usize = 1;

fn rawMsync(addr: [*]const u8, length: usize, flags: usize) isize {
    return @bitCast(syscall3(Syscall.msync, @intFromPtr(addr), length, flags));
}
```

**Completion Criteria:**
- [x] Typing `:w` saves changes to disk
- [x] Confirmation message displayed
- [x] Errors handled gracefully
- [x] MAP_PRIVATE → MAP_SHARED for write-back support

**Note:** Dirty page tracking is minimal (always saves full file). For production use, track specific modified byte ranges and only sync those pages.

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
2. **High Priority:** Phase 4 - File saving (basic completeness)
3. **High Priority:** Phase 5 - Command-line parsing (core usability)
4. **Medium Priority:** Phase 3 - ANSI diff (optimization - nice to have)
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

### Phase 7: Undo/Redo System ✅ COMPLETE

**Goal:** Implement Ctrl+Z undo functionality for basic editing operations

**Tasks:**
- [x] Add Operation struct for tracking insert/delete operations
- [x] Add undo buffer to EditorState (256 operations, ~2.5KB)
- [x] Record operations during character insertion
- [x] Handle Ctrl+Z (ASCII 26) for undo in main loop
- [x] Reverse operations (remove inserted chars, re-insert deleted chars)
- [x] Update cursor position after undo
- [x] Update footer help text to show Ctrl+Z undo

**Technical Details:**
```zig
const Operation = struct {
    op_type: enum { insert, delete },
    position: usize, // byte offset
    char: u8,       // character affected
};

fn recordOperation(editor_state: *EditorState, op: Operation) void {
    // Circular buffer implementation
}

fn undoOperation(data: [*]u8, editor_state: *EditorState) void {
    // Reverse last operation
}
```

**Completion Criteria:**
- [x] Ctrl+Z undoes last insert operation
- [x] Cursor position updated correctly after undo
- [x] Display refreshed after undo
- [x] Circular buffer prevents memory leaks
- [x] Footer shows "Ctrl+Z undo" in help text

**Binary Size Impact:** +~100 bytes for undo buffer and functions

---

## Advanced Features Roadmap (Updated)

### Phase 8: Delete/Backspace Support

**Goal:** Enable character and line deletion in insert mode

**Tasks:**
- Handle backspace key (ASCII 8 or 127) in insert mode
- Handle delete key (escape sequences)
- Shift bytes left to remove characters
- Update cursor position after deletion
- Record delete operations for undo
- Prevent deletion beyond file bounds

### Phase 9: Cursor Movement

**Goal:** Free cursor movement within file content

**Tasks:**
- Handle arrow keys (escape sequences: \x1b[A, \x1b[B, etc.)
- Handle vim-style movement (h/j/k/l keys)
- Constrain cursor within file bounds
- Update viewport scrolling when cursor moves outside visible area
- Handle line wrapping for cursor positioning

### Phase 10: Line Operations

**Goal:** Support line insertion and deletion

**Tasks:**
- Handle Enter key for line splitting
- Handle line deletion (dd command)
- Handle line joining operations
- Update cursor position after line operations
- Maintain proper line endings

---

*Last Updated: 2026-01-12*
*Phase 7 Complete | Undo/Redo Working*
