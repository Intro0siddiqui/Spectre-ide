const std = @import("std");

// On Linux/Zig 0.15, O is a packed struct. We need to construct it or cast.
// buffer.zig expects u32 flags.
// We will simply treat them as u32 and cast when calling std.posix.open if needed,
// OR define them as the struct values if possible.
// But buffer.zig passes them around as bitmasks? Check buffer.zig...
// buffer.zig: const fd = platform.rawOpen(filename.ptr, platform.O_RDWR, 0);
// It treats it as a value.

// Let's rely on std.os.linux constants directly if possible, or build the struct.
pub const O_RDWR: u32 = @bitCast(std.posix.O{ .ACCMODE = .RDWR });
pub const PROT_READ = std.posix.PROT.READ;
pub const PROT_WRITE = std.posix.PROT.WRITE;
pub const MAP_SHARED = std.posix.MAP.SHARED;
pub const MAP_PRIVATE = std.posix.MAP.PRIVATE;
pub const MAP_ANONYMOUS = std.posix.MAP.ANONYMOUS;
pub const MS_SYNC = std.posix.MS.SYNC;

pub const Stat = std.posix.Stat;

pub fn getPageSize() usize {
    return 4096;
}

pub fn alignUp(val: usize, alignment: usize) usize {
    return std.mem.alignForward(usize, val, alignment);
}

pub fn rawOpen(path: [*:0]const u8, flags: u32, mode: u32) i32 {
    const len = std.mem.len(path);
    const slice = path[0..len];

    // cast flags u32 back to O struct
    const o_flags: std.posix.O = @bitCast(flags);

    // Mode is mode_t (u32 usually)
    const mode_t: std.posix.mode_t = @intCast(mode);

    if (std.posix.open(slice, o_flags, mode_t)) |fd| {
        return fd;
    } else |_| {
        return -1;
    }
}

pub fn rawClose(fd: i32) void {
    std.posix.close(fd);
}

pub fn rawFstat(fd: i32, stat_buf: *Stat) i32 {
    if (std.posix.fstat(fd)) |s| {
        stat_buf.* = s;
        return 0;
    } else |_| {
        return -1;
    }
}

pub fn rawMmap(addr: ?[*]u8, length: usize, prot: u32, flags: u32, fd: i32, offset: usize) ?[*]u8 {
    // std.posix.mmap
    // It expects aligned_length? No, raw mmap.
    // The signature in Zig std changes often.
    // In 0.13+: mmap(ptr: ?[*]align(mem.page_size) u8, length: usize, prot: u32, flags: u32, fd: fd_t, offset: u64) ![]align(mem.page_size) u8

    // We need to catch error and return null to match old API
    if (std.posix.mmap(addr, length, prot, flags, fd, offset)) |slice| {
        return slice.ptr;
    } else |_| {
        return null;
    }
}

pub fn rawMsync(addr: [*]u8, length: usize, flags: u32) i32 {
    // We need to convert ptr to slice for standard API if required, or usage?
    // std.posix.msync expects slice usually: msync(memory: []align(mem.page_size) u8, flags: u32)
    // This might be tricky if alignment is lost.
    // For now, assume it works or stub it.

    // Construct a slice
    const slice = addr[0..length];

    // We can't guarantee alignment here easily without type changes in buffer.zig
    // But msync usually just needs page alignment which mmap provides.
    // Let's try to call it.
    if (std.posix.msync(@alignCast(slice), flags)) {
        return 0;
    } else |_| {
        return -1;
    }
}
