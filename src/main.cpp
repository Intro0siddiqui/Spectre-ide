#include <FL/Fl.H>
#include <FL/Fl_Double_Window.H>
#include "core/Editor.h"
#include "ui/EditorWidget.h"
#include <memory>
#include <iostream>

int main(int argc, char **argv) {
    // Initialize Core Editor
    auto editor = std::make_unique<core::Editor>();
    
    // Check args for file to open
    if (argc > 1) {
        editor->loadFile(argv[1]);
    }

    // Initialize Window
    Fl_Double_Window *window = new Fl_Double_Window(1200, 800, "Spectre-IDE C++");
    
    // Create Editor Widget
    ui::EditorWidget *editorWidget = new ui::EditorWidget(0, 0, 1200, 800, editor.get());
    
    // Setup handling
    window->resizable(editorWidget);
    window->end();
    window->show(argc, argv);
    
    return Fl::run();
}
