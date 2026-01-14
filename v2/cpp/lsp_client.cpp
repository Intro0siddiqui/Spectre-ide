// C++ LSP Client for Spectre-IDE
// Minimal implementation using fork/exec and JSON

#include "lsp_client.h"
#include <unistd.h>
#include <sys/wait.h>
#include <cstring>
#include <cstdio>

static pid_t lsp_pid = -1;
static int stdin_pipe[2] = {-1, -1};
static int stdout_pipe[2] = {-1, -1};

extern "C" {

bool lsp_start(const char* server_path) {
    if (pipe(stdin_pipe) < 0) return false;
    if (pipe(stdout_pipe) < 0) {
        close(stdin_pipe[0]);
        close(stdin_pipe[1]);
        return false;
    }

    lsp_pid = fork();
    if (lsp_pid == 0) {
        // Child process
        close(stdin_pipe[1]);  // Close write end of stdin
        close(stdout_pipe[0]); // Close read end of stdout
        
        dup2(stdin_pipe[0], STDIN_FILENO);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        
        close(stdin_pipe[0]);
        close(stdout_pipe[1]);
        
        execlp(server_path, server_path, nullptr);
        _exit(127);
    } else if (lsp_pid > 0) {
        // Parent process
        close(stdin_pipe[0]);  // Close read end of stdin
        close(stdout_pipe[1]); // Close write end of stdout
        return true;
    }
    
    return false;
}

void lsp_stop() {
    if (stdin_pipe[1] >= 0) {
        close(stdin_pipe[1]);
        stdin_pipe[1] = -1;
    }
    if (stdout_pipe[0] >= 0) {
        close(stdout_pipe[0]);
        stdout_pipe[0] = -1;
    }
    if (lsp_pid > 0) {
        waitpid(lsp_pid, nullptr, 0);
        lsp_pid = -1;
    }
}

bool lsp_send(const char* json, size_t len) {
    if (stdin_pipe[1] < 0) return false;
    
    char header[64];
    int header_len = snprintf(header, sizeof(header), "Content-Length: %zu\r\n\r\n", len);
    
    if (write(stdin_pipe[1], header, header_len) != header_len) return false;
    if (write(stdin_pipe[1], json, len) != (ssize_t)len) return false;
    
    return true;
}

ssize_t lsp_recv(char* buffer, size_t max_len) {
    if (stdout_pipe[0] < 0) return -1;
    return read(stdout_pipe[0], buffer, max_len);
}

} // extern "C"
