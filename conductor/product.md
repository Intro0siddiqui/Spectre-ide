# Initial Concept
A minimalist freestanding text editor built with Zig, targeting binary size under 600KB with zero-copy memory-mapped I/O architecture. It aims to be a standalone binary that provides a high-performance, IDE-like experience (LSP, terminal integration) without terminal runtime dependencies.

# Product Guide - Spectre-IDE

## Vision
Spectre-IDE is designed for embedded systems engineers and minimalists who require a robust, zero-dependency development environment. It combines the speed of memory-mapped file access with modern features like LSP and a built-in terminal relay, all while maintaining a tiny footprint.

## Core Features
- **Zero-Copy Architecture:** Uses `mmap` for efficient file handling, even for files larger than RAM.
- **Freestanding Build:** No LibC dependency; all syscalls are implemented via direct Linux x86_64 assembly.
- **LSP Integration:** Support for multiple language servers (zls, clangd, etc.) for semantic highlighting and diagnostics.
- **Interactive Terminal Relay:** 
    - **Toggle Access:** Use `Ctrl+` ` or `Ctrl+T` to open/close the terminal interface.
    - **View Modes:** Supports both fullscreen overlays and floating popup windows.
    - **Full Functionality:** Provides a fully interactive shell session, allowing users to run builds, tests, or background tasks just like in a native terminal.
- **Mouse Support:** Integrated mouse interaction for navigation and selection.
- **Headless Command Relay:** Future-ready architecture for AI agents to execute commands and capture output with zero idle tax.

## Target Audience
- **Embedded Systems Engineers:** Professionals working in restricted environments where a standalone, minimal-binary editor is essential.
- **Workflow Minimalists:** Users who prefer terminal-centric workflows but want the features of an IDE without the bloat of heavy runtimes.

## Design Philosophy
- **Performance First:** Prioritize low latency and minimal binary size (target < 600KB).
- **Orchestration, not Babysitting:** Inherit the host system's shell environment and safety guards.
- **Transient UI:** Use "Ghost Panes" and overlays for secondary tasks like terminal output to keep the core editing experience clean.
