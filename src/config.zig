// config.zig - Configuration system for Spectre-IDE

pub const Config = struct {
    tab_size: usize = 4,
    syntax_highlighting: bool = false,
    auto_lsp: bool = false,
    lsp_server: [32]u8 = undefined,
    lsp_server_len: usize = 0,
    status_line: bool = true,
    line_numbers: bool = false,
    auto_indent: bool = true,
    wrap_lines: bool = false,
};

pub const CONFIG_BUFFER_SIZE = 512;

pub fn initDefault() Config {
    return .{};
}
