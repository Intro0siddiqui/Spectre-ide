// syscalls.zig - Process and pipe syscalls for LSP client
// Linux x86_64 syscalls for freestanding mode

pub const STDIN_FILENO = 0;
pub const STDOUT_FILENO = 1;
pub const STDERR_FILENO = 2;

pub const Syscall = enum(usize) {
    read = 0,
    write = 1,
    open = 2,
    close = 3,
    stat = 4,
    fstat = 5,
    lseek = 8,
    mmap = 9,
    mprotect = 10,
    munmap = 11,
    brk = 12,
    ioctl = 16,
    pread64 = 17,
    pwrite64 = 18,
    readv = 19,
    writev = 20,
    access = 21,
    pipe = 22,
    msync = 26,
    dup = 32,
    dup2 = 33,
    pause = 23,
    nanosleep = 35,
    getpid = 39,
    socket = 41,
    connect = 42,
    accept = 43,
    sendto = 44,
    recvfrom = 45,
    sendmsg = 46,
    recvmsg = 47,
    shutdown = 48,
    bind = 49,
    listen = 50,
    getsockname = 51,
    getpeername = 52,
    socketpair = 53,
    setsockopt = 54,
    getsockopt = 55,
    fork = 57,
    execve = 59,
    exit = 60,
    wait4 = 61,
    kill = 62,
    uname = 63,
    semget = 64,
    semop = 65,
    semctl = 66,
    shmdt = 67,
    shmget = 68,
    shmat = 69,
    shmctl = 70,
    dup3 = 24,
    pipe2 = 293,
    fcntl = 72,
    rt_sigaction = 13,
    rt_sigreturn = 15,
};

pub inline fn syscall0(number: Syscall) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
        : .{ .rcx = true, .r11 = true });
}

// ... (syscall1, 2, 3)

pub fn rawFcntl(fd: usize, cmd: usize, arg: usize) usize {
    return syscall3(.fcntl, fd, cmd, arg);
}

pub const F_GETFL: usize = 3;
pub const F_SETFL: usize = 4;

pub inline fn syscall1(number: Syscall, arg1: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
        : .{ .rcx = true, .r11 = true });
}

pub inline fn syscall2(number: Syscall, arg1: usize, arg2: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
        : .{ .rcx = true, .r11 = true });
}

pub inline fn syscall3(number: Syscall, arg1: usize, arg2: usize, arg3: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
        : .{ .rcx = true, .r11 = true });
}

pub inline fn syscall4(number: Syscall, arg1: usize, arg2: usize, arg3: usize, arg4: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
        : .{ .rcx = true, .r11 = true });
}

pub inline fn syscall5(number: Syscall, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
        : .{ .rcx = true, .r11 = true });
}

pub inline fn syscall6(number: Syscall, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize, arg6: usize) usize {
    return asm volatile ("syscall"
        : [ret] "={rax}" (-> usize),
        : [number] "{rax}" (@intFromEnum(number)),
          [arg1] "{rdi}" (arg1),
          [arg2] "{rsi}" (arg2),
          [arg3] "{rdx}" (arg3),
          [arg4] "{r10}" (arg4),
          [arg5] "{r8}" (arg5),
          [arg6] "{r9}" (arg6),
        : .{ .rcx = true, .r11 = true });
}

pub fn rawRead(fd: usize, buf: [*]u8, count: usize) isize {
    return @as(isize, @bitCast(syscall3(.read, fd, @intFromPtr(buf), count)));
}

pub fn rawWrite(fd: usize, buf: [*]const u8, count: usize) isize {
    return @as(isize, @bitCast(syscall3(.write, fd, @intFromPtr(buf), count)));
}

pub fn rawClose(fd: usize) usize {
    return syscall1(.close, fd);
}

pub fn rawPipe(fd: *[2]i32) usize {
    return syscall1(.pipe, @intFromPtr(fd));
}

pub const O_NONBLOCK: usize = 2048;
pub const O_CLOEXEC: usize = 524288;

pub fn rawPipe2(fd: *[2]i32, flags: usize) usize {
    return syscall2(.pipe2, @intFromPtr(fd), flags);
}

pub fn rawDup2(oldfd: usize, newfd: usize) usize {
    return syscall2(.dup2, oldfd, newfd);
}

pub fn rawFork() usize {
    return syscall0(.fork);
}

pub fn rawExecve(path: [*]const u8, argv: [*]const ?[*]const u8, envp: [*]const ?[*]const u8) usize {
    return syscall3(.execve, @intFromPtr(path), @intFromPtr(argv), @intFromPtr(envp));
}

pub fn rawWaitpid(pid: usize, status: *i32, options: usize) usize {
    return syscall4(.wait4, pid, @intFromPtr(status), options, 0);
}

pub fn rawExit(status: usize) noreturn {
    _ = syscall1(.exit, status);
    unreachable;
}

pub fn rawGetPid() usize {
    return syscall0(.getpid);
}

pub fn rawNanosleep(req: *const timespec, rem: ?*timespec) usize {
    return syscall2(.nanosleep, @intFromPtr(req), if (rem) |p| @intFromPtr(p) else 0);
}

pub const SIGINT = 2;
pub const SA_RESTORER = 0x04000000;

pub const sigset_t = u64;

pub const Sigaction = extern struct {
    handler: ?*const fn (i32) callconv(.C) void,
    flags: usize,
    restorer: ?*const fn () callconv(.C) void,
    mask: sigset_t,
};

pub fn rawSigaction(sig: i32, act: ?*const Sigaction, oact: ?*Sigaction) usize {
    return syscall4(.rt_sigaction, @as(usize, @bitCast(@as(isize, sig))), if (act) |a| @intFromPtr(a) else 0, if (oact) |o| @intFromPtr(o) else 0, 8);
}

pub const timespec = extern struct {
    tv_sec: isize,
    tv_nsec: isize,
};

pub fn sleep(seconds: usize) void {
    var req = timespec{ .tv_sec = @as(isize, @intCast(seconds)), .tv_nsec = 0 };
    _ = rawNanosleep(&req, null);
}

pub fn msleep(milliseconds: usize) void {
    var req = timespec{
        .tv_sec = @as(isize, @intCast(milliseconds / 1000)),
        .tv_nsec = @as(isize, @intCast((milliseconds % 1000) * 1000000)),
    };
    _ = rawNanosleep(&req, null);
}

pub fn usleep(microseconds: usize) void {
    var req = timespec{
        .tv_sec = 0,
        .tv_nsec = @as(isize, @intCast(microseconds * 1000)),
    };
    _ = rawNanosleep(&req, null);
}

pub fn nullTerminatedLength(str: [*]const u8) usize {
    var len: usize = 0;
    while (str[len] != 0) : (len += 1) {}
    return len;
}

pub fn createEnvp() [*]const ?[*]const u8 {
    var env_ptrs: [4]?[*]const u8 = .{ null, null, null, null };
    env_ptrs[0] = "PATH=/usr/bin:/bin".ptr;
    env_ptrs[1] = "HOME=/root".ptr;
    env_ptrs[2] = "TERM=xterm".ptr;
    env_ptrs[3] = null;
    const result: [*]const ?[*]const u8 = @ptrCast(env_ptrs[0..4].ptr);
    return result;
}

pub fn splitPath(path: [*]const u8) [][*:0]const u8 {
    _ = path;
    return &.{};
}
