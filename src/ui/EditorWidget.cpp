#include "EditorWidget.h"
#include <FL/fl_draw.H>
#include <FL/Enumerations.H>
#include <iostream>

namespace ui {

EditorWidget::EditorWidget(int x, int y, int w, int h, core::Editor* editor)
    : Fl_Widget(x, y, w, h), editor(editor) {
}

void EditorWidget::draw() {
    // Draw background
    fl_color(0x28, 0x2a, 0x36); // #282a36 (Dracula BG)
    fl_rectf(x(), y(), w(), h());

    auto* buffer = editor->getCurrentBuffer();
    if (!buffer) return;

    // Draw Text
    fl_font(FL_COURIER, 16);
    fl_color(0xf8, 0xf8, 0xf2); // #f8f8f2 (Dracula FG)
    
    int row = 0;
    for (const auto& line : buffer->lines) {
        drawText(row, 0, line);
        row++;
    }

    drawCursor();
}

void EditorWidget::drawText(int row, int col, const std::string& text) {
    if (text.empty()) return;
    int X = x() + col * char_width;
    int Y = y() + (row + 1) * char_height - 4; // Baseline adjustment
    fl_draw(text.c_str(), X, Y);
}

void EditorWidget::drawCursor() {
    int cx = x() + editor->cursor_col * char_width;
    int cy = y() + editor->cursor_row * char_height;
    
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
            
            if (key == FL_Left) editor->moveLeft();
            else if (key == FL_Right) editor->moveRight();
            else if (key == FL_Up) editor->moveUp();
            else if (key == FL_Down) editor->moveDown();
            
            redraw();
            return 1;
        }
    }
    return Fl_Widget::handle(event);
}

} // namespace ui
