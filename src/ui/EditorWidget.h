#pragma once
#include <FL/Fl_Widget.H>
#include "../core/Editor.h"

namespace ui {

class EditorWidget : public Fl_Widget {
public:
    EditorWidget(int x, int y, int w, int h, core::Editor* editor);
    
    void draw() override;
    int handle(int event) override;

private:
    core::Editor* editor;
    
    // Theme
    const unsigned int BG_COLOR = 0x282a3600; // Dracula BG
    const unsigned int FG_COLOR = 0xf8f8f200; // Dracula FG
    const unsigned int CURSOR_COLOR = 0xffffff88; // Semi-transparent white
    
    // Layout
    int char_width = 10;
    int char_height = 18;
    
    void drawText(int row, int col, const std::string& text);
    void drawCursor();
};

} // namespace ui
