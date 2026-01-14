// C++ LSP Client - C interface header

#ifndef LSP_CLIENT_H
#define LSP_CLIENT_H

#include <stddef.h>
#include <stdbool.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

// Start LSP server process
bool lsp_start(const char* server_path);

// Stop LSP server
void lsp_stop(void);

// Send JSON-RPC message to server
bool lsp_send(const char* json, size_t len);

// Receive data from server (non-blocking if no data)
ssize_t lsp_recv(char* buffer, size_t max_len);

#ifdef __cplusplus
}
#endif

#endif // LSP_CLIENT_H
