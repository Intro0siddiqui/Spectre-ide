const syscalls = @import("syscalls.zig");

pub const CommandRelay = struct {
    pid: usize = 0,
    read_fd: usize = 0,
    write_fd: usize = 0,

    pub fn init() CommandRelay {
        return .{};
    }

    pub fn spawn(self: *CommandRelay, command: []const u8) !void {
        var pipefd: [2]i32 = undefined;
        // Check for error return from pipe (usually 0 on success)
        const ret = syscalls.rawPipe(&pipefd);
        if (@as(isize, @bitCast(ret)) < 0) return error.PipeFailed;
        
        const pid = syscalls.rawFork();
        const pid_signed: isize = @bitCast(pid);
        
        if (pid_signed < 0) return error.ForkFailed;

        if (pid == 0) {
            // Child
            _ = syscalls.rawClose(@as(usize, @intCast(pipefd[0])));
            _ = syscalls.rawDup2(@as(usize, @intCast(pipefd[1])), syscalls.STDOUT_FILENO);
            _ = syscalls.rawDup2(@as(usize, @intCast(pipefd[1])), syscalls.STDERR_FILENO);
            _ = syscalls.rawClose(@as(usize, @intCast(pipefd[1])));
            
            // Parse command
            var argv: [16]?[*:0]const u8 = undefined;
            var argc: usize = 0;
            
            var cmd_buf: [256]u8 = undefined;
            if (command.len >= 256) syscalls.rawExit(1);
            @memcpy(cmd_buf[0..command.len], command);
            cmd_buf[command.len] = 0;
            
            var i: usize = 0;
            var in_arg = false;
            
            while (i < command.len) {
                if (cmd_buf[i] == ' ') {
                    if (in_arg) {
                        cmd_buf[i] = 0;
                        in_arg = false;
                    }
                } else {
                    if (!in_arg) {
                        if (argc < 15) {
                            argv[argc] = @ptrCast(&cmd_buf[i]);
                            argc += 1;
                        }
                        in_arg = true;
                    }
                }
                i += 1;
            }
            argv[argc] = null;
            
            var env_ptrs: [4]?[*]const u8 = .{ null, null, null, null };
            env_ptrs[0] = "PATH=/usr/bin:/bin".ptr;
            env_ptrs[1] = "HOME=/root".ptr;
            env_ptrs[2] = "TERM=xterm".ptr;
            env_ptrs[3] = null;
            const envp: [*]const ?[*]const u8 = @ptrCast(&env_ptrs);
            
            if (argc > 0) {
                // Cast to [*]const ?[*]const u8 is tricky
                // execve expects pointer to array of pointers
                _ = syscalls.rawExecve(argv[0].?, @ptrCast(&argv), envp);
            }
            syscalls.rawExit(127);
        } else {
            // Parent
            _ = syscalls.rawClose(@as(usize, @intCast(pipefd[1])));
            self.pid = pid;
            const read_fd = @as(usize, @intCast(pipefd[0]));
            self.read_fd = read_fd;
            
            // Set O_NONBLOCK
            const flags = syscalls.rawFcntl(read_fd, syscalls.F_GETFL, 0);
            if (@as(isize, @bitCast(flags)) >= 0) {
                _ = syscalls.rawFcntl(read_fd, syscalls.F_SETFL, flags | syscalls.O_NONBLOCK);
            }
        }
    }

    pub fn readOutput(self: *CommandRelay, buffer: []u8) usize {
        const n = syscalls.rawRead(self.read_fd, buffer.ptr, buffer.len);
        if (n < 0) return 0;
        return @as(usize, @intCast(n));
    }

    pub fn kill(self: *CommandRelay) void {
        if (self.pid > 0) {
            _ = syscalls.rawClose(self.read_fd);
            var status: i32 = 0;
            _ = syscalls.rawWaitpid(self.pid, &status, 0);
            self.pid = 0;
        }
    }
};