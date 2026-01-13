.global _start
.type _start, @function
_start:
    xor %rbp, %rbp
    mov %rsp, %rdi
    and $-16, %rsp
    call zig_start
    mov %rax, %rdi
    mov $60, %rax
    syscall
