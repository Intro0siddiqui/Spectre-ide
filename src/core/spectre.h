#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void spectre_init();
void spectre_insert_char(uint8_t c);
void spectre_delete_char(bool backspace);

// 0: Up, 1: Down, 2: Left, 3: Right
void spectre_move(int op);
void spectre_undo();

size_t spectre_get_cursor_row();
size_t spectre_get_cursor_col();
size_t spectre_get_line_count();

// Returns length written. out_ptr must be at least max_len size.
size_t spectre_get_line_content(size_t row, char* out_ptr, size_t max_len);

#ifdef __cplusplus
}
#endif
