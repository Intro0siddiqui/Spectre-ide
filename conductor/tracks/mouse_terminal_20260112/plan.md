# Plan - Mouse Support and Terminal Relay Foundation

## Phase 1: Mouse Support (Phase 18)
- [x] Task: Research and define ANSI mouse escape sequences (X10 vs SGR). [commit: 731c964]
- [x] Task: Update `src/main.zig` event loop to enable mouse reporting. [commit: e528680]
- [x] Task: Implement mouse sequence parser in `src/main.zig`. [commit: 9f37b51]
- [x] Task: Map mouse click events to cursor positioning logic. [commit: 9f37b51]
- [x] Task: Map scroll wheel events to viewport `line_offset` adjustment. [commit: 9f37b51]
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Mouse Support' (Protocol in workflow.md)

## Phase 2: Terminal Relay Foundation
- [ ] Task: Add `fork`, `execve`, `pipe`, `dup2`, and `waitpid` syscalls to `src/syscalls.zig`.
- [ ] Task: Implement basic process spawning logic in a new `src/terminal.zig` or `src/main.zig`.
- [ ] Task: Implement non-blocking output capture from the child process.
- [ ] Task: Add a simple "Ghost Pane" UI element to display captured output.
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Terminal Relay Foundation' (Protocol in workflow.md)
