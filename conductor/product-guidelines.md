# Product Guidelines - Spectre-IDE

## Documentation and Prose
- **Technical Conciseness:** Standard documentation and internal comments must be brief, direct, and focused on implementation details (Prose Style A).
- **Educational Deep-Dives:** For major architectural features (like the Terminal Relay or LSP client), provide detailed, structured notation to explain complex low-level logic and design decisions (Prose Style C).

## Visual Identity and TUI
- **Theming Engine:** The interface must support a plugin-based theme system, allowing users to customize colors and aesthetics similar to Neovim.
- **Purposeful Defaults:** Default themes should use color sparingly to highlight critical information (errors, modes, syntax) without cluttering the minimalist aesthetic.

## Architecture and Structure
- **Syscall Isolation:** All platform-specific assembly and Linux syscalls must be isolated in `src/syscalls.zig`. Core editor logic should remain platform-agnostic by calling these wrappers (Architecture A).
- **Zero-Dependency Mandate:** No third-party Zig packages or C libraries are permitted. All functionality, including JSON parsing and protocol handling, must be implemented from scratch within the project (Architecture C).

## Quality and Performance
- **Binary Size Management:** Maintain a target budget of < 600KB. While high-value features may justify expanding this limit, every major addition must be profiled for its size impact (Policy A).
- **Continuous Profiling:** Regularly analyze binary bloat using assembly inspection and size checks to optimize frequently used paths (Policy C).

## Error Handling
- **Non-Fatal Resilience:** The editor should attempt to recover from non-critical errors silently to prevent workflow interruption (Policy C).
- **In-Editor Reporting:** Critical errors that cannot be recovered must be reported via the status bar or a dedicated diagnostic pane rather than crashing the process (Policy B).
