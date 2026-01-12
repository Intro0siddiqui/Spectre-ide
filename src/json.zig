// json.zig - Minimal JSON builder for LSP messages
// Supports building JSON-RPC 2.0 requests and notifications

const MAX_JSON_SIZE = 2048;
const MAX_MESSAGE_SIZE = 4096;

pub const JsonBuilder = struct {
    buf: [MAX_JSON_SIZE]u8,
    len: usize,

    pub fn init() JsonBuilder {
        return .{
            .buf = undefined,
            .len = 0,
        };
    }

    pub fn reset(self: *JsonBuilder) void {
        self.len = 0;
    }

    pub fn append(self: *JsonBuilder, bytes: []const u8) void {
        if (self.len + bytes.len < MAX_JSON_SIZE) {
            @memcpy(self.buf[self.len..], bytes);
            self.len += bytes.len;
        }
    }

    pub fn appendChar(self: *JsonBuilder, c: u8) void {
        if (self.len < MAX_JSON_SIZE) {
            self.buf[self.len] = c;
            self.len += 1;
        }
    }

    pub fn appendString(self: *JsonBuilder, str: []const u8) void {
        self.appendChar('"');
        var i: usize = 0;
        while (i < str.len) : (i += 1) {
            const c = str[i];
            if (c == '"') {
                self.append("\\\"");
            } else if (c == '\\') {
                self.append("\\\\");
            } else if (c == '\n') {
                self.append("\\n");
            } else if (c == '\r') {
                self.append("\\r");
            } else if (c == '\t') {
                self.append("\\t");
            } else {
                self.appendChar(c);
            }
        }
        self.appendChar('"');
    }

    pub fn appendInt(self: *JsonBuilder, value: usize) void {
        var num_buf: [32]u8 = undefined;
        var num_len: usize = 0;
        var n = value;
        if (n == 0) {
            num_buf[0] = '0';
            num_len = 1;
        } else {
            while (n > 0) {
                num_buf[num_len] = '0' + @as(u8, @intCast(n % 10));
                num_len += 1;
                n /= 10;
            }
            var i: usize = 0;
            while (i < num_len / 2) : (i += 1) {
                const tmp = num_buf[i];
                num_buf[i] = num_buf[num_len - 1 - i];
                num_buf[num_len - 1 - i] = tmp;
            }
        }
        self.append(num_buf[0..num_len]);
    }

    pub fn getSlice(self: *const JsonBuilder) []const u8 {
        return self.buf[0..self.len];
    }
};

pub fn buildInitializeRequest(builder: *JsonBuilder, process_id: usize, uri: []const u8) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{");
    builder.append("\"processId\":");
    builder.appendInt(process_id);
    builder.append(",\"clientInfo\":{\"name\":\"Spectre-IDE\",\"version\":\"1.0.0\"},");
    builder.append("\"rootUri\":\"");
    builder.append(uri);
    builder.append("\",\"capabilities\":{}");
    builder.append("}}");
}

pub fn buildInitializedNotification(builder: *JsonBuilder) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}");
}

pub fn buildDidOpenNotification(builder: *JsonBuilder, uri: []const u8, language_id: []const u8, version: usize, text: []const u8) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{");
    builder.append("\"textDocument\":{\"uri\":\"");
    builder.append(uri);
    builder.append("\",\"languageId\":\"");
    builder.append(language_id);
    builder.append("\",\"version\":");
    builder.appendInt(version);
    builder.append(",\"text\":");
    builder.appendString(text);
    builder.append("}}}");
}

pub fn buildDidChangeNotification(builder: *JsonBuilder, uri: []const u8, version: usize, text: []const u8) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{");
    builder.append("\"textDocument\":{\"uri\":\"");
    builder.append(uri);
    builder.append("\",\"version\":");
    builder.appendInt(version);
    builder.append("},\"contentChanges\":[{\"text\":");
    builder.appendString(text);
    builder.append("}]}}");
}

pub fn buildSemanticTokensRequest(builder: *JsonBuilder, id: usize, uri: []const u8) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"id\":");
    builder.appendInt(id);
    builder.append(",\"method\":\"textDocument/semanticTokens/full\",\"params\":{");
    builder.append("\"textDocument\":{\"uri\":\"");
    builder.append(uri);
    builder.append("\"}}}");
}

pub fn buildHoverRequest(builder: *JsonBuilder, id: usize, uri: []const u8, line: usize, character: usize) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"id\":");
    builder.appendInt(id);
    builder.append(",\"method\":\"textDocument/hover\",\"params\":{");
    builder.append("\"textDocument\":{\"uri\":\"");
    builder.append(uri);
    builder.append("\"},\"position\":{\"line\":");
    builder.appendInt(line);
    builder.append(",\"character\":");
    builder.appendInt(character);
    builder.append("}}}");
}

pub fn buildDefinitionRequest(builder: *JsonBuilder, id: usize, uri: []const u8, line: usize, character: usize) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"id\":");
    builder.appendInt(id);
    builder.append(",\"method\":\"textDocument/definition\",\"params\":{");
    builder.append("\"textDocument\":{\"uri\":\"");
    builder.append(uri);
    builder.append("\"},\"position\":{\"line\":");
    builder.appendInt(line);
    builder.append(",\"character\":");
    builder.appendInt(character);
    builder.append("}}}");
}

pub fn buildShutdownRequest(builder: *JsonBuilder, id: usize) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"id\":");
    builder.appendInt(id);
    builder.append(",\"method\":\"shutdown\",\"params\":null}");
}

pub fn buildExitNotification(builder: *JsonBuilder) void {
    builder.reset();
    builder.append("{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":null}");
}

pub fn parseContentLength(header_buf: [*]const u8, header_len: usize) ?usize {
    var i: usize = 0;
    const prefix = "Content-Length: ";
    const prefix_len = 16;

    while (i + prefix_len <= header_len and i < prefix_len) : (i += 1) {
        if (header_buf[i] != prefix[i]) return null;
    }

    var value_start: usize = prefix_len;
    while (value_start < header_len and header_buf[value_start] == ' ') : (value_start += 1) {}

    var value: usize = 0;
    var has_digit = false;
    var j = value_start;
    while (j < header_len and header_buf[j] >= '0' and header_buf[j] <= '9') : (j += 1) {
        value = value * 10 + @as(usize, @intCast(header_buf[j] - '0'));
        has_digit = true;
    }

    return if (has_digit) value else null;
}

pub fn findJsonStart(buf: [*]const u8, len: usize) usize {
    var i: usize = 0;
    while (i + 1 < len) : (i += 1) {
        if (buf[i] == '\r' and buf[i + 1] == '\n') {
            return i + 2;
        }
    }
    return len;
}

pub fn getMessageSize(content_length: usize) usize {
    return content_length + 4; // Content-Length line + \r\n\r\n
}

pub const LSPMessage = struct {
    header_buf: [64]u8,
    header_len: usize,
    json_buf: [MAX_JSON_SIZE]u8,
    json_len: usize,
    total_len: usize,

    pub fn init() LSPMessage {
        return .{
            .header_buf = undefined,
            .header_len = 0,
            .json_buf = undefined,
            .json_len = 0,
            .total_len = 0,
        };
    }

    pub fn buildMessage(self: *LSPMessage, json_builder: *JsonBuilder) void {
        const json_bytes = json_builder.getSlice();
        self.json_len = json_bytes.len;
        @memcpy(self.json_buf[0..json_bytes.len], json_bytes);

        const header = "Content-Length: ";
        const header_line = "\r\n\r\n";
        const content_len_str_len = self.countDigits(self.json_len);

        self.header_len = header.len + content_len_str_len + header_line.len;
        var pos: usize = 0;

        @memcpy(self.header_buf[pos..][0..header.len], header);
        pos += header.len;

        var num_buf: [16]u8 = undefined;
        self.writeNumber(self.json_len, num_buf[0..]);
        @memcpy(self.header_buf[pos..][0..content_len_str_len], num_buf);
        pos += content_len_str_len;

        @memcpy(self.header_buf[pos..][0..header_line.len], header_line);
        pos += header_line.len;

        self.total_len = self.header_len + self.json_len;
    }

    fn countDigits(self: *LSPMessage, n: usize) usize {
        _ = self;
        if (n == 0) return 1;
        var count: usize = 0;
        var num = n;
        while (num > 0) : (count += 1) {
            num /= 10;
        }
        return count;
    }

    pub fn writeNumber(self: *LSPMessage, n: usize, buf: []u8) void {
        _ = self;
        var num_buf: [16]u8 = undefined;
        var len: usize = 0;
        var num = n;
        if (num == 0) {
            num_buf[0] = '0';
            len = 1;
        } else {
            while (num > 0) {
                num_buf[len] = '0' + @as(u8, @intCast(num % 10));
                len += 1;
                num /= 10;
            }
            var i: usize = 0;
            while (i < len / 2) : (i += 1) {
                const tmp = num_buf[i];
                num_buf[i] = num_buf[len - 1 - i];
                num_buf[len - 1 - i] = tmp;
            }
        }
        @memcpy(buf, num_buf[0..len]);
    }
};
