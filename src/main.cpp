#include <FL/Fl.H>
#include <FL/Fl_Double_Window.H>
#include "core/spectre.h"
#include "ui/EditorWidget.h"
#include <iostream>

int main(int argc, char **argv) {
    // Initialize Zig Core
    spectre_init();
    
    // Initialize Window
    Fl_Double_Window *window = new Fl_Double_Window(1200, 800, "Spectre-IDE (Hybrid)");
    
    // Create Editor Widget (No args needed now as it uses global API)
    ui::EditorWidget *editorWidget = new ui::EditorWidget(0, 0, 1200, 800);
    
    // Setup handling
    window->resizable(editorWidget);
    window->end();
    window->show(argc, argv);
    
    return Fl::run();
}
