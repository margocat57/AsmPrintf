; nasm -f elf64 -o prc2.o printf_c_in_asm2.s
; gcc -std=c2x -no-pie -o prc2 prc2.o 

; как сделать с pie с учетом ошибки
; /usr/bin/ld: prc2.o: relocation R_X86_64_PC32 against symbol `printf@@GLIBC_2.2.5' can not be used when making a PIE object; recompile with -fPIE

section .data
string    db "Result", 10, "%d%s%x%d%%%c%b", 10, 0
teststr   db "love", 0
testdigit dq 10

section .text

global main
extern printf

; %d %s %x %d %% %c %b\n, -1, "love", 1802, 100, 33, 126
main:
        push rbp
        mov rbp, rsp

        sub rsp, 8  ; выравнивание

        push 126                 ; %b arg
        mov r9, 33               ; %c arg (testdigit ptr) 
        mov r8, 100              ; %d arg
        mov rcx, 1802            ; %x arg
        lea rdx, [rel teststr]   ; %s arg
        mov rsi, -1              ; %d arg
        lea rdi, [rel string]    ; string ptr

        xor rax, rax  ; количество дробных аргументов
        call printf

        add rsp, 8 

        mov rsp, rbp
        pop rbp

        ret


section .note.GNU-stack