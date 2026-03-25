; nasm -f elf64 -o prc2.o printf_c_in_asm2.s
; gcc -std=c2x -o prc2 prc2.o 

section .data
string    db "Result", 10, "%d %s %x", 10, 0
teststr   db "abcs", 0
testdigit dq 10

section .text

global main
extern printf
main:
        push rbp
        mov rbp, rsp

        mov rcx, 23457           ; %x arg
        lea rdx, [rel teststr]   ; %s arg
        mov rsi, -10             ; %d arg
        lea rdi, [rel string]    ; string ptr

        xor eax, eax  ; количество дробных аргументов
        call printf wrt ..plt ; в pie зарещены прямые ссылки на внешние символы

        mov rsp, rbp
        pop rbp

        xor eax, eax ; return with exit code 0
        ret


section .note.GNU-stack