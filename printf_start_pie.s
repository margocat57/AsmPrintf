; MY ASSEMBLY PRINTF IMPLEMENTATION
; nasm -f elf64 -o asm.o printf_start_pie.s  
; gcc -std=c2x -o program test3.c asm.o


; !TODO избавиться от -no-pie

STRING_END     equ 0x0
HOT_SYMBOL     equ '%'
START_SPEC     equ 'b'
NUM_OF_SPEC    equ 'x' - 'b'
TRUE           equ 1
FALSE          equ 0
SIGN_BIT       equ 0x80000000
HEX_SHIFT      equ -4
BIN_SHIFT      equ -2


section .text

global _printf                 

;------------------------------------------------------------------
; Prints string using format specifiers:
; %b, %c, %d, %o, %p, %s, %x
;
; Entry(cdecl): rdi - first param  (string with format specifiers)
;               rsi - second param (argument fot 1st format spec)
;               rdx - third param  (argument fot 2nd format spec)
;               rcx - 4th param    (argument fot 3d format spec)
;               r8  - 5th param
;               r9 - 6th param
;   (at stack): return adress
;               7th param
;
; Func called: printf_string, fflush_buffer
;
; Exit: string outputted to stdout
;
; Destr: func called destr regs
;------------------------------------------------------------------
_printf:            mov qword [rel printed_symb], 0
                    pop r10       ; put return adress(cdecl)

                    ; rdi, rsi, rdx, rcx, r8, r9 
                    push r9
                    push r8
                    push rcx
                    push rdx
                    push rsi
                    push rdi

                    push rbp
                    mov rbp, rsp

                    mov rsi, [rbp + 8]   ; rsi = pointer to string
                    add rbp, 16          ; rbp = first param
                    call printf_string   ;output string

                    call fflush_buffer

                    mov rax, [rel printed_symb]
                    pop rbp

                    pop rdi
                    pop rsi
                    pop rdx
                    pop rcx
                    pop r8
                    pop r9

                    push r10  ; ret adress
                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Prints string(to buffer or if buffer overflow occured - to stdout)
;
; Entry: rsi --> pointer to string with format specifiers
;        rbp - first argument for format specifiers
;
; Exit: does not return anything
;
; Func called: process_hot_symb, output_char
;
; Destr: rsi, rdi + func called destr regs
;------------------------------------------------------------------
printf_string:      

.output_loop:       cmp byte [rsi], STRING_END
                    je .exit_printf

                    cmp byte [rsi], HOT_SYMBOL
                    jne .not_hot_symb
                    call process_hot_symb
                    jmp .output_loop

.not_hot_symb:      mov dil, byte [rsi]
                    call output_char
                    inc rsi
                    jmp .output_loop

.exit_printf:        ret                                          
;------------------------------------------------------------------


;------------------------------------------------------------------
; Processing format specifiers
;
; Entry: rsi --> pointer to string with format specifiers
;        rbp - first argument for format specifiers
;        at stack - arguments for format specifiers
;
; Exit: does not return anything
;
; Func called: output_binary, output_char, output_decimal, output_octal, 
;              output_pointer, output_string, output_hex
;
; Destr: rsi, rdi, r8, rbp + func called destr regs
;------------------------------------------------------------------
process_hot_symb:   inc rsi

                    cmp byte [rsi], '%'
                    jne process_spec

incorr_or_percent:  xor rdi, rdi
                    mov dil, '%'
                    call output_char
                    jmp exit_switch

process_spec:       xor rdi, rdi
                    mov dil, byte [rsi]
                    sub dil, START_SPEC

                    cmp dil, NUM_OF_SPEC
                    ja incorr_or_percent

                    lea r9, [rel SwitchTable]     ; r9 = rip + offset SwitchTable
                    mov r8, [r9 + 8*rdi]
                    jmp r8

binary:             mov edi, dword [rbp]
                    add rbp, 8
                    call output_binary
                    jmp exit_switch

char:               mov edi, dword [rbp]
                    add rbp, 8
                    call output_char
                    jmp exit_switch

decimal:            movsxd rdi, dword [rbp] ; знаковое расширешение 4 байт из памяти по адресу rbp
                    add rbp, 8
                    call output_decimal
                    jmp exit_switch

octal:              mov edi, dword [rbp]
                    add rbp, 8
                    call output_octal
                    jmp exit_switch

pointer:            mov rdi, [rbp]
                    add rbp, 8
                    call output_pointer
                    jmp exit_switch

string:             mov rdi, [rbp]
                    add rbp, 8
                    call output_string
                    jmp exit_switch    

hex:                mov edi, dword [rbp]
                    add rbp, 8
                    call output_hex
                    jmp exit_switch               

exit_switch:        inc rsi
                    ret      
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %b format specifier
;
; Entry:  rdi - argument for format specifier
;
; Exit: does not return anything
;
; Func called: output_char
;
; Destr: rcx, rdi + func called destr regs
;------------------------------------------------------------------
output_binary:      
                    test rdi, rdi
                    jz .is_zero

                    xor rcx, rcx
                    bsr ecx, edi      ; старший единичный бит
                    and ecx, BIN_SHIFT

.output_loop:       cmp cl, 0
                    jl .exit_output

                    push rdi
                    shr edi, cl
                    and edi, 0b1
                    lea r9, [rel BinConvStr]            ; r9 = rip + offset BinConvStr
                    movzx rdi, byte [r9 + rdi]  ; прочитать байт из памяти/регистра и заполнить старшие биты нулями
                    call output_char

                    pop rdi
                    sub cl, 1
                    jmp .output_loop

.is_zero:           mov dil, '0'
                    call output_char

.exit_output:       ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %d format specifier
;
; Entry: rdi - argument for format specifier
;
; Exit: does not return anything
;
; Func called: output_char
;
; Destr: rax, rcx, rdx, rdi + func called destr regs
;------------------------------------------------------------------
output_decimal:     test rdi, rdi          ; SF = 1 if digit < 0
                    jns .process_positive

                    push rdi
                    xor rdi, rdi
                    mov dil, '-'
                    call output_char
                    pop rdi
                    neg rdi

.process_positive:  mov r9, 10    ; r9 = delitel
                    mov rax, rdi  ; rax = digit
                    xor rcx, rcx  ; rcx = 0 (for symbols count)

.divide_loop:       xor rdx, rdx

                    div r9        ; частное - rax, остаток rdx
                    add rdx, '0'
                    push rdx
                    inc rcx

                    test rax, rax
                    jz .output_result

                    jmp .divide_loop

.output_result:     pop rdi
                    call output_char
                    loop .output_result

                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %o format specifier
;
; Entry: rdi - argument for format specifier
;
; Exit: does not return anything
;
; Func called: output_char
;
; Destr: rcx, rdi + func called destr regs
;------------------------------------------------------------------
output_octal:       test rdi, rdi
                    jz .is_zero

                    xor rcx, rcx
                    bsr ecx, edi
                    lea r9, [rel OctShiftTable]            ; r9 = rip + offset OctShiftTable 
                    movzx ecx, byte [r9 + rcx]

.output_loop:       cmp cl, 0
                    jl .exit_output

                    push rdi
                    shr edi, cl
                    and edi, 0b111
                    lea r9, [rel OctConvStr]            ; r9 = rip + offset OctConvStr
                    movzx rdi, byte [r9 + rdi]  ; прочитать байт из памяти/регистра и заполнить старшие биты нулями
                    call output_char

                    pop rdi
                    sub cl, 3
                    jmp .output_loop

.is_zero:           mov dil, '0'
                    call output_char

.exit_output:       ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %p format specifier
;
; Entry: rdi - argument for format specifier
;
; Exit: does not return anything
;
; Func called: output_char, output_string
;
; Destr: rcx, rdi + func called destr regs
;------------------------------------------------------------------
output_pointer:     push rdi
                    lea rdi, [rel ptr_]
                    call output_string
                    pop rdi

                    test rdi, rdi
                    jz .is_zero

                    xor rcx, rcx
                    bsr rcx, rdi
                    and rcx, HEX_SHIFT

.output_loop:       cmp cl, 0
                    jl .exit_output

                    push rdi
                    shr rdi, cl
                    and rdi, 0b1111
                    lea r9, [rel HighHexConvStr]            ; r9 = rip + offset HighHexConvStr
                    movzx rdi, byte [r9 + rdi]  ; прочитать байт из памяти/регистра и заполнить старшие биты нулями
                    call output_char

                    pop rdi
                    sub cl, 4
                    jmp .output_loop

.is_zero:           mov dil, '0'
                    call output_char

.exit_output:       ret
;-----------------------------------------------------------------

;------------------------------------------------------------------
; Process %s format specifier
;
; Entry: rdi - argument for format specifier
;
; Exit: does not return anything
;
; Func called: output_char, my_strlen
;
; Destr: rcx, rdi, r9 + func called destr regs
;------------------------------------------------------------------
output_string:      mov r9, rdi
                    call my_strlen  ; rcx = num of symb

                    test rcx, rcx
                    jz .exit_output

                    cmp rcx, buf_len - 1
                    jb .out_str_by_char

                    call fflush_buffer
                    call put_str_to_stdout

                    ret
                    
.out_str_by_char:   mov dil, byte [r9] 
                    call output_char
                    inc r9
                    loop .out_str_by_char 

.exit_output:       ret             
;------------------------------------------------------------------

;------------------------------------------------------------------
; Find length of string
;
; Entry: rdi - string
;
; Exit: rcx - length of string
;
; Destr: rax, rdi
;------------------------------------------------------------------
my_strlen:          xor rcx, rcx
                    dec rcx

                    mov al, 0x0

                    repne scasb    ; while(rdi!=al){rdi++}

                    not rcx 
                    dec rcx
                    ret
;------------------------------------------------------------------


;------------------------------------------------------------------
; Process %x format specifier
;
; Entry: rdi - argument for format specifier
;
; Exit: does not return anything
;
; Func called: output_char
;
; Destr: rcx, rdi + func called destr regs
;------------------------------------------------------------------
output_hex:         
                    test rdi, rdi
                    jz .is_zero

                    xor rcx, rcx
                    bsr ecx, edi        ; найти первый единичный бит в числе
                    and ecx, HEX_SHIFT

.output_loop:       cmp cl, 0
                    jl .exit_output

                    push rdi
                    shr edi, cl
                    and edi, 1111b
                    lea r9, [rel LowHexConvStr]            ; r9 = rip + offset LowHexConvStr
                    movzx rdi, byte [r9 + rdi]  ; прочитать байт из памяти/регистра и заполнить старшие биты нулями
                    call output_char

                    pop rdi
                    sub cl, 4
                    jmp .output_loop

.is_zero:           mov dil, '0'
                    call output_char

.exit_output:       ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Put char to buffer and check buffer overflow
;
; Entry: dil - char for output
;
; Exit: does not return anything
;
; Func called: fflush_buffer
;
; Destr: r11 + func called destr regs
;------------------------------------------------------------------
output_char:        push r9
                    mov r11, [rel curr_buf_size]
                    lea r9, [rel buffer]            ; r9 = rip + offset buffer
                    mov byte [r9 + r11], dil
                    inc qword [rel curr_buf_size]

                    cmp dil, 10d
                    jne .continue
                    call fflush_buffer

.continue:          cmp qword [rel curr_buf_size], buf_len - 1
                    jb .exit_output
                    call fflush_buffer

.exit_output:       pop r9
                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Put data of buffer to stdout(using syscall)
;
; Exit: [printed_symb] incremented by number of symbols output to stdout
;       [curr_buf_size] = 0 
;
; Destr: r11
;------------------------------------------------------------------
fflush_buffer:      mov r11, [rel curr_buf_size]
                    add [rel printed_symb], r11

                    push rax
                    push rdi
                    push rsi
                    push rdx

                    push rcx   ; ret adress in syscall
                    push r11   ; flags in syscall

                    mov rax, 0x01      ; write64
                    mov rdi, 1         ; stdout
                    lea rsi, [rel buffer]
                    mov rdx, [rel curr_buf_size]    ; strlen (buffer)
                    syscall

                    mov qword [rel curr_buf_size], 0

                    pop r11   ; flags in syscall
                    pop rcx   ; ret adress in syscall

                    pop rdx
                    pop rsi
                    pop rdi
                    pop rax

                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Put data of string to stdout(using syscall)
;
; Entry: r9 ---> pointer to string
;        rcx - number of symbols to write
;
; Exit: [printed_symb] incremented by number of symbols output to stdout
;------------------------------------------------------------------
put_str_to_stdout:  add [rel printed_symb], rcx

                    push rax
                    push rdi
                    push rsi
                    push rdx

                    push rcx   ; ret adress in syscall
                    push r11   ; flags in syscall

                    mov rax, 0x01      ; write64
                    mov rdi, 1         ; stdout
                    mov rsi, r9
                    mov rdx, rcx       ; strlen (buffer)
                    syscall

                    pop r11   ; flags in syscall
                    pop rcx   ; ret adress in syscall

                    pop rdx
                    pop rsi
                    pop rdi
                    pop rax

                    ret
;------------------------------------------------------------------

section .data

align 8
SwitchTable:
                                dq binary           ; %b
                                dq char             ; %c
                                dq decimal          ; %d
            times ('o'-'d'-1)   dq incorr_or_percent
                                dq octal            ; %o
                                dq pointer          ; %p
            times ('s'-'p'-1)   dq incorr_or_percent 
                                dq string           ; %s
            times ('x'-'s'-1)   dq incorr_or_percent
                                dq hex              ; %x

LowHexConvStr  db "0123456789abcdef"
HighHexConvStr db "0123456789ABCDEF"
BinConvStr     db "01"
OctConvStr     db "01234567"
OctShiftTable  db 0,0,0,3,3,3,6,6,6,9,9,9,12,12,12,15,15,15,18,18,18,21,21,21,24,24,24,27,27,27,30,30

printed_symb dq 0

curr_buf_size dq 0

ptr_ db '0x', 0x0

buffer  db 10 dup(0)
buf_len equ $ - buffer

section .note.GNU-stack