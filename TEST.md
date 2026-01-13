# Testing Spectre-IDE

## Build for Testing

To build with debug symbols and no optimizations (easier to debug with `gdb` or `lldb`):

```bash
zig build -Doptimize=Debug
```

## Running the Application

```bash
./zig-out/bin/spectre-ide src/main.zig
```

## Manual Verification Steps (Phase 1: Mouse Support)

1.  **Build and run the IDE:** `./zig-out/bin/spectre-ide src/main.zig`
2.  **Test Cursor Positioning:** Click with your mouse on any line in the file. Confirm the cursor moves to the clicked location.
3.  **Test Scrolling:** Use your mouse scroll wheel. Confirm the viewport scrolls up and down (3 lines per scroll notch).
4.  **Exit:** Press `q` to exit.

## Current Known Issues

### Segmentation Fault in `renderViewport`

Currently, the application crashes with a `Segmentation fault (core dumped)` during the initial render.

**Symptoms:**
- The application enters `zig_start` and successfully maps the file and allocates `EditorState`.
- It enters `renderViewport` and clears the `screen_buffer`.
- It successfully renders the "mode" part of the status bar.
- It crashes during or immediately after converting the line/column numbers to strings for the status bar.

**Debug Output:**
```
Debug: zig_start entered, sp=...
Debug: argc=2
Debug: Opening: src/main.zig
Debug: File opened
Debug: File size determined
Debug: File mmapped
Debug: Allocating EditorState
Debug: EditorState allocated
Debug: EditorState zeroed
Debug: Starting first render
Debug: renderViewport entered
Debug: screen_buffer cleared
Debug: status bar mode done
Debug: line num start
Debug: line num end
Segmentation fault (core dumped)
```

**Suspected Cause:**
- Possible stack overflow in `renderViewport` due to large local buffers or recursion (though no recursion is evident).
- Potential memory corruption related to `ScreenBuffer` or `EditorState` pointers.
- Misalignment or invalid access in the integer-to-string conversion logic.
