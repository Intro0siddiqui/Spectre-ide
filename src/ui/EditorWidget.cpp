#include "EditorWidget.h"
#include <FL/fl_draw.H>
#include <FL/Enumerations.H>
#include <iostream>
#include <vector>

namespace ui {

EditorWidget::EditorWidget(int x, int y, int w, int h)
    : Fl_Widget(x, y, w, h) {
}

void EditorWidget::draw() {
    // Draw background
    fl_color(0x28, 0x2a, 0x36); // #282a36 (Dracula BG)
    fl_rectf(x(), y(), w(), h());

    // Draw Text
    fl_font(FL_COURIER, 16);
    fl_color(0xf8, 0xf8, 0xf2); // #f8f8f2 (Dracula FG)
    
    size_t line_count = spectre_get_line_count();
    // Simple render loop (only render what's needed in real app)
    // For now render first 50 lines to verify
    size_t max_lines = line_count > 50 ? 50 : line_count;
    
    char buffer[1024];
    for (size_t i = 0; i < max_lines; ++i) {
        size_t len = spectre_get_line_content(i, buffer, 1024);
        if (len > 0) {
            drawText(i, 0, buffer);
        }
    }

    drawCursor();
}

void EditorWidget::drawText(int row, int col, const char* text) {
    int X = x() + col * char_width;
    int Y = y() + (row + 1) * char_height - 4; // Baseline adjustment
    fl_draw(text, X, Y); // fl_draw handles null-terminated strings
}

void EditorWidget::drawCursor() {
    size_t r = spectre_get_cursor_row();
    size_t c = spectre_get_cursor_col();

    int cx = x() + c * char_width;
    int cy = y() + r * char_height;
    
    // Draw cursor rectangle
    fl_color(0xff, 0xff, 0xff);
    fl_rectf(cx, cy, 2, char_height); // Thin cursor
}

int EditorWidget::handle(int event) {
    switch (event) {
        case FL_FOCUS:
        case FL_UNFOCUS:
            return 1;
            
        case FL_KEYDOWN: {
            int key = Fl::event_key();
            // TODO: Proper key mapping 
            // Mapping FLTK keys to Zig API op codes
            if (key == FL_Up) spectre_move(0);
            else if (key == FL_Down) spectre_move(1);
            else if (key == FL_Left) spectre_move(2);
            else if (key == FL_Right) spectre_move(3);
            else if (key == FL_BackSpace) spectre_delete_char(true);
            else if (key == 'u') spectre_undo(); // Simple undo binding
            else {
                 const char* text = Fl::event_text();
                 if (text && strlen(text) > 0) {
                     spectre_insert_char(text[0]);
                 }
            }
            
            redraw();
            return 1;
        }
    }
    return Fl_Widget::handle(event);
}

} // namespace ui
