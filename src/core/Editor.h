#pragma once
#include <string>
#include <vector>
#include <memory>

namespace core {

struct Buffer {
    std::string filename;
    std::vector<std::string> lines;
    bool modified = false;

    // Basic buffer operations
    void insertChar(size_t row, size_t col, char c);
    void deleteChar(size_t row, size_t col);
    void splitLine(size_t row, size_t col);
    void joinLine(size_t row);
};

enum class Mode {
    Normal,
    Insert,
    Command,
    Search
};

class Editor {
public:
    Editor();
    
    // Core state
    size_t cursor_row = 0;
    size_t cursor_col = 0;
    Mode mode = Mode::Normal;
    
    // Buffer management
    std::vector<std::unique_ptr<Buffer>> buffers;
    size_t current_buffer_idx = 0;

    // Operations
    void loadFile(const std::string& filename);
    Buffer* getCurrentBuffer();
    
    // Cursor movement
    void moveUp();
    void moveDown();
    void moveLeft();
    void moveRight();
    
    // Actions
    void handleInput(int key);
    
private:
    void createScratchpad();
};

} // namespace core
