# Tech Stack - Spectre-IDE

## Core Architecture
- **Language:** Zig (0.16.0-dev)
- **Runtime:** Freestanding (No LibC).
- **Syscall Layer:** Direct Linux x86_64 assembly integration via `src/syscalls.zig`.
- **Memory Management:** 
    - **Files:** Zero-copy via `mmap` with `MAP_SHARED` for persistence.
    - **LSP/Dynamic Buffers:** Anonymous memory mappings with `mremap` (Strategy C) to handle large data without a traditional heap.
    - **Global State:** Fixed-size static buffers for predictable footprint.

## Performance & Build Strategy
- **Hybrid Optimization:** 
    - **Default:** `.ReleaseSmall` to keep binary under 600KB.
    - **Hot Paths:** The **Renderer** (TUI diffing/ANSI generation) is compiled with maximum efficiency settings or inline assembly to minimize input latency.
- **Consultation Rule:** Any feature increasing binary size significantly must be profiled and presented for approval.

## Terminal Relay (Low-RAM Architecture)
- **Control:** Async Polling (via `poll`/`epoll`) to manage PTY streams alongside editor input without blocking (Strategy C).
- **Relay Mechanism:** Passthrough Relay (Strategy A) for native shell performance and full feature compatibility (Zsh/colors/etc.).
- **Memory Optimization:** A hybrid approach using a **Small RAM Ring Buffer** for current-view throughput and a **Temporary Circular File (mmap)** for scrollback history, ensuring RAM usage remains flat regardless of terminal output volume.

## LSP Client
- **Communication:** JSON-RPC 2.0 over PTY/Pipes.
- **Parsing:** Custom minimal parser with `mremap`-backed buffers to handle large semantic token payloads or diagnostics without heap exhaustion.

## Build System
- Custom `build.zig` implementation to support the freestanding target and hybrid optimization flags for specific modules.
