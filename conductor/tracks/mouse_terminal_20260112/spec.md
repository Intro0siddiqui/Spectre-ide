# Specification - Mouse Support and Terminal Relay Foundation

## Overview
This track implements Phase 18 (Mouse Support) and the foundational infrastructure for the Headless Command Relay (Terminal interaction). This fulfills the goal of making Spectre-IDE a more capable standalone IDE while maintaining its freestanding, zero-dependency architecture.

## Requirements
- **Mouse Support:**
    - Enable X10/SGR mouse reporting in the TUI.
    - Parse mouse event sequences (`\x1b[M...` or `\x1b[<...`).
    - Support clicking to position the cursor.
    - Support scroll wheel for viewport scrolling.
- **Terminal Relay Foundation:**
    - Implement `rawFork()`, `rawExecve()`, `rawWaitpid()`, and `rawPipe()` in `src/syscalls.zig`.
    - Create a `CommandRelay` module to spawn `/bin/sh` or `/bin/zsh`.
    - Implement basic output capture to a fixed-size buffer.

## Technical Constraints
- No LibC or external libraries.
- Binary size must be monitored (target < 600KB).
- Memory usage must remain flat (fixed buffers or `mmap`/`mremap`).
