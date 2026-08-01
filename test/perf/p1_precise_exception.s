        .intel_syntax noprefix
        .text
        .globl p1_fault_sequence
        .def p1_fault_sequence; .scl 2; .type 32; .endef
        .seh_proc p1_fault_sequence
p1_fault_sequence:
        mov rax, qword ptr [rsp]
        mov qword ptr [rip + p1_saved_return], rax
        push rbx
        .seh_pushreg rbx
        push rbp
        .seh_pushreg rbp
        push rsi
        .seh_pushreg rsi
        push rdi
        .seh_pushreg rdi
        push r12
        .seh_pushreg r12
        push r13
        .seh_pushreg r13
        push r14
        .seh_pushreg r14
        push r15
        .seh_pushreg r15
        .seh_endprologue

        mov rax, 0x1111111122222222
        mov rbx, 0x3333333344444444
        mov rcx, 0x5555555566666666
        mov rdx, 0x7777777788888888
        mov rsi, 0x99999999aaaaaaaa
        mov rdi, 0xbbbbbbbbcccccccc
        mov rbp, 0xddddddddeeeeeeee
        mov r8,  0x0123456789abcdef
        mov r9,  0xfedcba9876543210
        mov r10, 0x13579bdf2468ace0
        mov r11, 0x0f1e2d3c4b5a6978
        mov r12, 0x1020304050607080
        mov r13, 0x8877665544332211
        mov r14, 0xa5a5a5a55a5a5a5a
        xor r15d, r15d
        cmp rax, rax

        .globl p1_fault_site
p1_fault_site:
        mov qword ptr [r15], rax
        .globl p1_resume_site
p1_resume_site:
        pop r15
        pop r14
        pop r13
        pop r12
        pop rdi
        pop rsi
        pop rbp
        pop rbx
        mov r10, qword ptr [rip + p1_saved_return]
        cmp qword ptr [rsp], r10
        jne p1_return_slot_corrupt
        mov eax, 1
        ret
p1_return_slot_corrupt:
        int3
        .seh_endproc

        .data
        .balign 8
        .globl p1_saved_return
p1_saved_return:
        .quad 0
