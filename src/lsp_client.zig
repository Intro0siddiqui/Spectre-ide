// lsp_client.zig - Complete LSP client implementation for Spectre-IDE
// Supports clangd, zls, and other LSP servers via JSON-RPC 2.0 over stdio

const std = @import("std");
const Syscalls = @import("syscalls.zig");
const Json = @import("json.zig");

const MAX_MESSAGE_SIZE = 4096;
const MAX_TOKEN_COUNT = 4096;
const MESSAGE_BUFFER_SIZE = 8192;

pub const LSPClient = struct {
    child_pid: ?usize = null,
    stdin_fd: ?usize = null,
    stdout_fd: ?usize = null,
    json_builder: Json.JsonBuilder,
    message: Json.LSPMessage,
    message_buffer: [MESSAGE_BUFFER_SIZE]u8,
    buffer_len: usize = 0,
    next_id: usize = 1,
    initialized: bool = false,

    pub fn init() LSPClient {
        return .{
            .child_pid = null,
            .stdin_fd = null,
            .stdout_fd = null,
            .json_builder = Json.JsonBuilder.init(),
            .message = Json.LSPMessage.init(),
            .message_buffer = undefined,
            .buffer_len = 0,
            .next_id = 1,
            .initialized = false,
        };
    }

    pub fn deinit(self: *LSPClient) void {
        if (self.stdin_fd) |fd| {
            _ = Syscalls.rawClose(fd);
        }
        if (self.stdout_fd) |fd| {
            _ = Syscalls.rawClose(fd);
        }
        self.* = init();
    }

    pub fn startServer(self: *LSPClient, server_name: [*]const u8, args: [*]const ?[*]const u8) bool {
        var pipe_stdin: [2]i32 = undefined;
        var pipe_stdout: [2]i32 = undefined;

        if (Syscalls.rawPipe(&pipe_stdin) != 0) return false;
        if (Syscalls.rawPipe(&pipe_stdout) != 0) {
            _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdin[0])));
            _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdin[1])));
            return false;
        }

        const pid = Syscalls.rawFork();
        if (pid == 0) {
            _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdin[1])));
            _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdout[0])));

            _ = Syscalls.rawDup2(@as(usize, @intCast(pipe_stdin[0])), 0);
            _ = Syscalls.rawDup2(@as(usize, @intCast(pipe_stdout[1])), 1);

            _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdin[0])));
            _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdout[1])));

            const envp = Syscalls.createEnvp();
            _ = Syscalls.rawExecve(server_name, args, envp);

            Syscalls.rawExit(127);
        } else if (pid > 0) {
            _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdin[0])));
            _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdout[1])));

            self.child_pid = pid;
            self.stdin_fd = @as(usize, @intCast(pipe_stdin[1]));
            self.stdout_fd = @as(usize, @intCast(pipe_stdout[0]));

            return true;
        }

        _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdin[0])));
        _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdin[1])));
        _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdout[0])));
        _ = Syscalls.rawClose(@as(usize, @intCast(pipe_stdout[1])));
        return false;
    }

    pub fn stopServer(self: *LSPClient) void {
        if (self.stdin_fd) |fd| {
            _ = Syscalls.rawClose(fd);
            self.stdin_fd = null;
        }
        if (self.stdout_fd) |fd| {
            _ = Syscalls.rawClose(fd);
            self.stdout_fd = null;
        }
        if (self.child_pid) |pid| {
            var status: i32 = 0;
            _ = Syscalls.rawWaitpid(pid, &status, 0);
            self.child_pid = null;
        }
        self.initialized = false;
    }

    pub fn sendMessage(self: *LSPClient, json: []const u8) bool {
        const header = "Content-Length: ";
        const header_len = header.len;
        var content_len: usize = json.len;
        var content_len_str_len: usize = 0;
        if (content_len == 0) {
            content_len_str_len = 1;
        } else {
            while (content_len > 0) : (content_len_str_len += 1) {
                content_len /= 10;
            }
        }
        const newline = "\r\n\r\n";

        if (self.stdin_fd) |fd| {
            var pos: usize = 0;

            @memcpy(self.message_buffer[0..header_len], header);
            pos += header_len;

            var num_buf: [16]u8 = undefined;
            self.message.writeNumber(json.len, &num_buf);
            @memcpy(self.message_buffer[pos..][0..content_len_str_len], num_buf[0..content_len_str_len]);
            pos += content_len_str_len;

            @memcpy(self.message_buffer[pos..][0..newline.len], newline);
            pos += newline.len;

            @memcpy(self.message_buffer[pos..][0..json.len], json);

            const total_len = pos + json.len;
            const written = Syscalls.rawWrite(fd, self.message_buffer[0..total_len].ptr, total_len);

            return @as(usize, @bitCast(written)) == total_len;
        }
        return false;
    }

    pub fn readMessage(self: *LSPClient) ?[]const u8 {
        if (self.stdout_fd == null) return null;

        var header_buf: [64]u8 = undefined;
        var header_len: usize = 0;
        var found_double_crlf = false;

        while (header_len < 64) {
            const byte_read = Syscalls.rawRead(self.stdout_fd.?, &header_buf, 1);
            if (byte_read < 1) return null;
            const byte = @as(u8, @intCast(byte_read));
            header_buf[header_len] = byte;
            header_len += 1;

            if (header_len >= 4) {
                const last4 = header_buf[header_len - 4 .. header_len];
                if (last4[0] == '\r' and last4[1] == '\n' and last4[2] == '\r' and last4[3] == '\n') {
                    found_double_crlf = true;
                    break;
                }
            }
        }

        if (!found_double_crlf) return null;

        const content_length = Json.parseContentLength(&header_buf, header_len) orelse return null;

        if (content_length > MAX_MESSAGE_SIZE) return null;

        const json_start = Json.findJsonStart(&header_buf, header_len);
        const header_bytes = header_buf[json_start..header_len];
        const remaining = content_length -| header_bytes.len;

        var json_buf: [MAX_MESSAGE_SIZE]u8 = undefined;
        @memcpy(json_buf[0..header_bytes.len], header_bytes);

        if (remaining > 0) {
            const dest_ptr = @as([*]u8, @ptrCast(&json_buf[header_bytes.len]));
            const bytes_read = Syscalls.rawRead(self.stdout_fd.?, dest_ptr, remaining);
            if (@as(isize, @bitCast(bytes_read)) < @as(isize, @intCast(remaining))) {
                return null;
            }
        }

        return self.buffer_json(json_buf[0..content_length]);
    }

    fn buffer_json(self: *LSPClient, json: []const u8) ?[]const u8 {
        if (self.buffer_len + json.len < MESSAGE_BUFFER_SIZE) {
            @memcpy(self.message_buffer[self.buffer_len..], json);
            const result = self.message_buffer[0 .. self.buffer_len + json.len];
            self.buffer_len += json.len;
            return result;
        }
        self.buffer_len = 0;
        if (json.len < MESSAGE_BUFFER_SIZE) {
            @memcpy(self.message_buffer[0..json.len], json);
            self.buffer_len = json.len;
            return self.message_buffer[0..json.len];
        }
        return null;
    }

    pub fn clearBuffer(self: *LSPClient) void {
        self.buffer_len = 0;
    }

    pub fn sendInitialize(self: *LSPClient, uri: []const u8) bool {
        if (self.child_pid == null) return false;
        const pid = Syscalls.rawGetPid();

        Json.buildInitializeRequest(&self.json_builder, pid, uri);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn sendInitialized(self: *LSPClient) bool {
        Json.buildInitializedNotification(&self.json_builder);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn sendDidOpen(self: *LSPClient, uri: []const u8, language_id: []const u8, version: usize, text: []const u8) bool {
        Json.buildDidOpenNotification(&self.json_builder, uri, language_id, version, text);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn sendDidChange(self: *LSPClient, uri: []const u8, version: usize, text: []const u8) bool {
        Json.buildDidChangeNotification(&self.json_builder, uri, version, text);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn requestSemanticTokens(self: *LSPClient, uri: []const u8) bool {
        const id = self.next_id;
        self.next_id += 1;
        Json.buildSemanticTokensRequest(&self.json_builder, id, uri);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn requestHover(self: *LSPClient, uri: []const u8, line: usize, character: usize) bool {
        const id = self.next_id;
        self.next_id += 1;
        Json.buildHoverRequest(&self.json_builder, id, uri, line, character);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn requestDefinition(self: *LSPClient, uri: []const u8, line: usize, character: usize) bool {
        const id = self.next_id;
        self.next_id += 1;
        Json.buildDefinitionRequest(&self.json_builder, id, uri, line, character);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn sendShutdown(self: *LSPClient) bool {
        const id = self.next_id;
        self.next_id += 1;
        Json.buildShutdownRequest(&self.json_builder, id);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn sendExit(self: *LSPClient) bool {
        Json.buildExitNotification(&self.json_builder);
        const json = self.json_builder.getSlice();
        return self.sendMessage(json);
    }

    pub fn waitForResponse(self: *LSPClient, timeout_ms: usize) ?[]const u8 {
        var elapsed: usize = 0;
        const chunk_ms = 10;

        while (elapsed < timeout_ms) {
            if (self.readMessage()) |msg| {
                return msg;
            }
            Syscalls.msleep(chunk_ms);
            elapsed += chunk_ms;
        }
        return null;
    }

    pub fn waitForInitialize(self: *LSPClient) bool {
        var elapsed: usize = 0;
        const timeout_ms = 5000;
        const chunk_ms = 50;

        while (elapsed < timeout_ms) {
            if (self.readMessage()) |msg| {
                if (containsResult(msg)) {
                    self.initialized = true;
                    return true;
                }
            }
            Syscalls.msleep(chunk_ms);
            elapsed += chunk_ms;
        }
        return false;
    }
};

fn containsResult(json: []const u8) bool {
    var i: usize = 0;
    while (i < json.len) : (i += 1) {
        if (json[i] == 'r' and i + 6 <= json.len and std.mem.eql(u8, json[i .. i + 6], "\"result\"")) {
            return true;
        }
    }
    return false;
}

pub const SemanticToken = struct {
    delta_line: usize,
    delta_start: usize,
    length: usize,
    token_type: u32,
    token_modifiers: u32,
};

pub const SemanticTokens = struct {
    tokens: [MAX_TOKEN_COUNT]SemanticToken,
    count: usize = 0,
    data: []const u32 = &.{},

    pub fn init() SemanticTokens {
        return .{
            .tokens = undefined,
            .count = 0,
            .data = &.{},
        };
    }

    pub fn parse(self: *SemanticTokens, data: []const u32) void {
        self.count = 0;
        self.data = data;

        var line: usize = 0;
        var column: usize = 0;

        var i: usize = 0;
        while (i + 5 <= data.len and self.count < MAX_TOKEN_COUNT) : (i += 5) {
            const delta_line = data[i];
            const delta_start = data[i + 1];
            const length = data[i + 2];
            const token_type = data[i + 3];
            const token_modifiers = data[i + 4];

            line += delta_line;
            if (delta_line == 0) {
                column += delta_start;
            } else {
                column = delta_start;
            }

            self.tokens[self.count] = .{
                .delta_line = line,
                .delta_start = column,
                .length = length,
                .token_type = token_type,
                .token_modifiers = token_modifiers,
            };
            self.count += 1;
        }
    }
};

pub const Diagnostic = struct {
    line: usize,
    start_col: usize,
    end_col: usize,
    severity: u8,
    message: []const u8,
};

pub const Diagnostics = struct {
    items: [64]Diagnostic,
    count: usize = 0,

    pub fn init() Diagnostics {
        return .{
            .items = undefined,
            .count = 0,
        };
    }

    pub fn clear(self: *Diagnostics) void {
        self.count = 0;
    }

    pub fn add(self: *Diagnostics, line: usize, start_col: usize, end_col: usize, severity: u8, message: []const u8) void {
        if (self.count < self.items.len) {
            self.items[self.count] = .{
                .line = line,
                .start_col = start_col,
                .end_col = end_col,
                .severity = severity,
                .message = message,
            };
            self.count += 1;
        }
    }
};

pub const LspServerInfo = struct {
    name: [*]const u8,
    server_name: [*]const u8,
    args: [*]const ?[*]const u8,
};

pub const LSP_SERVERS = [_]LspServerInfo{
    .{ .name = "zls".ptr, .server_name = "zls".ptr, .args = &.{null} },
    .{ .name = "clangd".ptr, .server_name = "clangd".ptr, .args = &.{ "--background-index".ptr, null } },
    .{ .name = "pylsp".ptr, .server_name = "pylsp".ptr, .args = &.{null} },
    .{ .name = "rust-analyzer".ptr, .server_name = "rust-analyzer".ptr, .args = &.{null} },
    .{ .name = "gopls".ptr, .server_name = "gopls".ptr, .args = &.{null} },
    .{ .name = "none".ptr, .server_name = "".ptr, .args = &.{null} },
};

pub fn getLspServerByName(name: []const u8) ?*const LspServerInfo {
    var i: usize = 0;
    while (i < LSP_SERVERS.len) : (i += 1) {
        const server_name = LSP_SERVERS[i].name;
        const name_len = nullTerminatedLength(server_name);
        if (name.len == name_len) {
            var match = true;
            for (0..name_len) |j| {
                const sn = server_name[j];
                const un = name[j];
                const sn_lower = if (sn >= 'A' and sn <= 'Z') sn + 32 else sn;
                const un_lower = if (un >= 'A' and un <= 'Z') un + 32 else un;
                if (sn_lower != un_lower) {
                    match = false;
                    break;
                }
            }
            if (match) {
                return &LSP_SERVERS[i];
            }
        }
    }
    return null;
}

pub fn getLspServer(filename: [*]const u8) ?*const LspServerInfo {
    var i: usize = 0;
    while (i < LSP_SERVERS.len) : (i += 1) {
        const ext = LSP_SERVERS[i].extension;
        const ext_len = nullTerminatedLength(ext);
        const filename_len = nullTerminatedLength(filename);

        if (filename_len >= ext_len) {
            var match = true;
            for (0..ext_len) |j| {
                const fc = filename[filename_len - ext_len + j];
                const ec = ext[j];
                const fc_lower = if (fc >= 'A' and fc <= 'Z') fc + 32 else fc;
                const ec_lower = if (ec >= 'A' and ec <= 'Z') ec + 32 else ec;
                if (fc_lower != ec_lower) {
                    match = false;
                    break;
                }
            }
            if (match) {
                return &LSP_SERVERS[i];
            }
        }
    }
    return null;
}

fn nullTerminatedLength(str: [*]const u8) usize {
    var len: usize = 0;
    while (str[len] != 0) : (len += 1) {}
    return len;
}

pub fn makeFileUri(path: [*]const u8) [256]u8 {
    var uri: [256]u8 = undefined;
    var pos: usize = 0;

    uri[0..7].* = "file://".*;
    pos += 7;

    var i: usize = 0;
    while (path[i] != 0) : (i += 1) {
        const c = path[i];
        if (c == '/') {
            uri[pos] = '/';
            pos += 1;
        } else if (c == ':') {
            uri[pos] = '%';
            uri[pos + 1] = '3';
            uri[pos + 2] = 'A';
            pos += 3;
        } else {
            uri[pos] = c;
            pos += 1;
        }
    }

    uri[pos] = 0;
    return uri;
}
