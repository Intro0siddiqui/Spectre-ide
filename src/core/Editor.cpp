#include "Editor.h"
#include <fstream>
#include <iostream>

namespace core {

// --- Buffer Implementation ---

void Buffer::insertChar(size_t row, size_t col, char c) {
    if (row >= lines.size()) return;
    if (col > lines[row].length()) col = lines[row].length();
    
    lines[row].insert(col, 1, c);
    modified = true;
}

void Buffer::deleteChar(size_t row, size_t col) {
    if (row >= lines.size()) return;
    if (col >= lines[row].length()) return;
    
    lines[row].erase(col, 1);
    modified = true;
}

void Buffer::splitLine(size_t row, size_t col) {
    if (row >= lines.size()) return;
    if (col > lines[row].length()) col = lines[row].length();
    
    std::string current = lines[row];
    std::string next_line_content = current.substr(col);
    lines[row] = current.substr(0, col);
    
    lines.insert(lines.begin() + row + 1, next_line_content);
    modified = true;
}

void Buffer::joinLine(size_t row) {
    if (row + 1 >= lines.size()) return;
    
    std::string next = lines[row + 1];
    lines[row] += next;
    lines.erase(lines.begin() + row + 1);
    modified = true;
}

// --- Editor Implementation ---

Editor::Editor() {
    createScratchpad();
}

void Editor::createScratchpad() {
    auto buf = std::make_unique<Buffer>();
    buf->filename = "Scratchpad";
    buf->lines = {
        "// Spectre-IDE C++ Edition",
        "// -----------------------",
        "// Welcome to the new C++ core!",
        "",
        "fn main() {",
        "    println(\"Hello World\");",
        "}"
    };
    buffers.push_back(std::move(buf));
    current_buffer_idx = 0;
}

Buffer* Editor::getCurrentBuffer() {
    if (buffers.empty()) return nullptr;
    return buffers[current_buffer_idx].get();
}

void Editor::loadFile(const std::string& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) return;

    auto buf = std::make_unique<Buffer>();
    buf->filename = filename;
    
    std::string line;
    while (std::getline(file, line)) {
        buf->lines.push_back(line);
    }
    
    if (buf->lines.empty()) {
        buf->lines.push_back("");
    }
    
    buffers.push_back(std::move(buf));
    current_buffer_idx = buffers.size() - 1;
    cursor_row = 0;
    cursor_col = 0;
}

void Editor::moveUp() {
    if (cursor_row > 0) cursor_row--;
    // Clamp col
    Buffer* buf = getCurrentBuffer();
    if (buf && cursor_col > buf->lines[cursor_row].length()) {
        cursor_col = buf->lines[cursor_row].length();
    }
}

void Editor::moveDown() {
    Buffer* buf = getCurrentBuffer();
    if (!buf) return;
    
    if (cursor_row < buf->lines.size() - 1) cursor_row++;
    if (cursor_col > buf->lines[cursor_row].length()) {
        cursor_col = buf->lines[cursor_row].length();
    }
}

void Editor::moveLeft() {
    if (cursor_col > 0) cursor_col--;
}

void Editor::moveRight() {
    Buffer* buf = getCurrentBuffer();
    if (!buf) return;
    
    if (cursor_col < buf->lines[cursor_row].length()) cursor_col++;
}

void Editor::handleInput(int key) {
    // Basic stub for now, will connect to FLTK keys later
    // FLTK keys are often raw integers
}

} // namespace core
