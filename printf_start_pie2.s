; MY ASSEMBLY PRINTF IMPLEMENTATION
; nasm -f elf64 -o asm.o printf_start_pie2.s  
; gcc -fsanitize=address -std=c2x -o program test3.c asm.o

; objdump -M intel -d asm.o | less

STRING_END     equ 0x0
PERCENT        equ '%'
START_SPEC     equ 'b'
NUM_OF_SPEC    equ 'x' - 'b'

%macro PUSH_ARGS_REGS 0
    push r9 
    push r8
    push rcx
    push rdx
    push rsi
    push rdi
%endmacro

%macro POP_ARGS_REGS 0
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop r8
    pop r9
%endmacro

%macro PUSH_STDCALL_USED_REGS 0
    push rax
    push rdi
    push rsi
    push rdx

    push rcx   ; ret adress in syscall
    push r11   ; flags in syscall
%endmacro

%macro POP_STDCALL_USED_REGS 0
    pop r11   ; flags in syscall
    pop rcx   ; ret adress in syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
%endmacro

section .text

global _printf                 

;------------------------------------------------------------------
; Prints string using format specifiers:
; %b, %c, %d, %o, %p, %s, %x
;------------------------------------------------------------------
_printf:            mov qword [rel printed_symb], 0
                    pop r10       ; put return adress(cdecl)

                    PUSH_ARGS_REGS

                    push rbp
                    mov rbp, rsp

                    mov rsi, [rbp + 8]   ; rsi = pointer to string
                    add rbp, 16          ; rbp = first param
                    call printf_string   ;output string

                    call fflush_buffer

                    mov rax, [rel printed_symb]

                    pop rbp

                    POP_ARGS_REGS

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
; Destr: rsi, rdi, r9, rbp, r8, rdx, r11, rcx, rax
;------------------------------------------------------------------
printf_string:      

.output_loop:       cmp byte [rsi], STRING_END
                    je .exit_printf

                    cmp byte [rsi], PERCENT
                    je .percent

                    movzx edi, byte [rsi]
                    call output_char
                    inc rsi
                    jmp .output_loop

.percent:           call process_percent
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
; Destr: rsi, rdi, r9, rbp, r8, rdx, r11, rcx, rax
;------------------------------------------------------------------
process_percent:    inc rsi

                    cmp byte [rsi], PERCENT
                    jne process_spec

incorr_or_percent:  mov edi, PERCENT

                    call output_char
                    jmp exit_switch

process_spec:       movzx edi, byte [rsi] 
                    sub dil, START_SPEC

                    cmp dil, NUM_OF_SPEC
                    ja incorr_or_percent

                    lea r9, [rel SwitchTable]     ; r9 = rip + offset SwitchTable
                    jmp [r9 + 8*rdi]

binary:             mov edi, dword [rbp]
                    add rbp, 8

                    lea r9, [rel BinShiftTable]  
                    mov ecx, 1
                    call output_bin_hex_oct

                    jmp exit_switch

char:               mov edi, dword [rbp]
                    add rbp, 8 
                    call output_char
                    jmp exit_switch

decimal:            mov edi, dword [rbp] 
                    add rbp, 8
                    call output_decimal
                    jmp exit_switch

octal:              mov edi, dword [rbp]
                    add rbp, 8

                    lea r9, [rel OctShiftTable]  
                    mov ecx, 3
                    call output_bin_hex_oct

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

                    lea r9, [rel HexShiftTable]  
                    mov ecx, 4
                    call output_bin_hex_oct

                    jmp exit_switch               

exit_switch:        inc rsi
                    ret      
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %b/%x/%o format specifier
;
; Entry:  rdi - argument for format specifier
;         ecx - log2(base):
;               1 -> binary (base 2)
;               3 -> octal  (base 8)
;               4 -> hex    (base 16)
;         r9 ---> pointer to shift table that maps highest set bit index
;               to initial shift (BinShiftTable / OctShiftTable / HexShiftTable)
;
; Exit: does not return anything
;
; Destr: rcx, rdi, r8, rdx, r11, r9
;------------------------------------------------------------------
output_bin_hex_oct: test rdi, rdi
                    jz .is_zero

                    mov r8d, 1
                    shl r8d, cl
                    sub r8d, 1

                    movzx edx, cl 

                    xor ecx, ecx
                    bsr rcx, rdi                  ; старший единичный бит
                    movzx ecx, byte [r9 + rcx]    ; получаем с какого сдвига начнать
                    
                    lea r9, [rel LowHexConvStr]  ; r9 = rip + offset OctConvStr

.output_loop:       push rdi
                    shr rdi, cl
                    and rdi, r8
                    movzx edi, byte [r9 + rdi]  ; прочитать байт из памяти/регистра и заполнить старшие биты нулями
                    push r9
                    call output_char
                    pop r9

                    pop rdi
                    sub ecx, edx
                    jns .output_loop
                    ret

.is_zero:           mov dil, '0'
                    call output_char
                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %d format specifier
;
; Entry: rdi - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rax, rcx, rdx, rdi, r9, r11
;------------------------------------------------------------------
output_decimal:     test edi, edi          ; SF = 1 if digit < 0
                    jns .process_positive

                    push rdi
                    mov edi, '-'
                    call output_char
                    pop rdi

                    neg edi

.process_positive:  mov r9d, 10
                    mov eax, edi  ; rax = digit
                    xor ecx, ecx  ; rcx = 0 (for symbols count)

.divide_loop:       xor edx, edx
  
                    div r9d     ; частное - rax, остаток rdx

                    add edx, '0'
                    push rdx
                    inc ecx

                    test eax, eax
                    jnz .divide_loop

.output_result:     pop rdi
                    call output_char

                    dec ecx
                    jnz .output_result

.exit:              ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %p format specifier
;
; Entry: rdi - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rcx, rdi, r9, r11, rdx, r8
;------------------------------------------------------------------
output_pointer:     test rdi, rdi
                    jnz .not_zero

                    lea rdi, [rel ptrnul]
                    call output_string
                    ret

.not_zero:          push rdi
                    lea rdi, [rel ptr_]
                    call output_string
                    pop rdi

                    lea r9, [rel HexShiftTable]  
                    mov ecx, 4
                    call output_bin_hex_oct

.exit_output:       ret
;-----------------------------------------------------------------

;------------------------------------------------------------------
; Process %s format specifier
;
; Entry: rdi - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rcx, rdi, r9, r11, r8
;------------------------------------------------------------------
output_string:      test rdi, rdi
                    jnz .not_null

                    lea r8, [rel strnul]
                    mov rcx, nulstr_len
                    jmp .out_str_by_char

.not_null:          mov r8, rdi
                    call my_strlen  ; rcx = num of symb

                    test rcx, rcx
                    jz .exit_output

                    cmp rcx, buf_len - 1
                    jb .out_str_by_char

                    call fflush_buffer
                    call put_str_to_stdout

                    ret
                    
.out_str_by_char:   movzx edi, byte [r8] 
                    call output_char
                    inc r8
                    dec rcx

                    jnz .out_str_by_char

.exit_output:       ret             
;------------------------------------------------------------------

;------------------------------------------------------------------
; Find length of string
;
; Entry: rdi - string
;
; Exit: rcx - length of string
;------------------------------------------------------------------
my_strlen:          xor ecx, ecx

.cmp_loop:          cmp byte [rdi + rcx], 0
                    je .exit
                    inc rcx

                    jmp .cmp_loop

.exit:              ret
;------------------------------------------------------------------


;------------------------------------------------------------------
; Put char to buffer and check buffer overflow (line-buffered)
;
; Entry: dil - char for output
;
; Exit: does not return anything
;
; Destr: r11, r9
;------------------------------------------------------------------
output_char:        mov r11, [rel curr_buf_size]
                    lea r9, [rel buffer]            ; r9 = rip + offset buffer
                    mov byte [r9 + r11], dil
                    inc qword [rel curr_buf_size]

                    cmp dil, 10d
                    jne .continue
                    call fflush_buffer

.continue:          cmp qword [rel curr_buf_size], buf_len - 1
                    jb .exit_output
                    call fflush_buffer

.exit_output:       ret
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

                    PUSH_STDCALL_USED_REGS

                    mov rax, 0x01      ; write64
                    mov rdi, 1         ; stdout
                    lea rsi, [rel buffer]
                    mov rdx, [rel curr_buf_size]    ; strlen (buffer)
                    syscall

                    mov qword [rel curr_buf_size], 0

                    POP_STDCALL_USED_REGS

                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Put data of string to stdout(using syscall)
;
; Entry: r8 ---> pointer to string
;        rcx - number of symbols to write
;
; Exit: [printed_symb] incremented by number of symbols output to stdout
;------------------------------------------------------------------
put_str_to_stdout:  add [rel printed_symb], rcx

                    PUSH_STDCALL_USED_REGS

                    mov rax, 0x01      ; write64
                    mov rdi, 1         ; stdout
                    mov rsi, r8
                    mov rdx, rcx       ; strlen (buffer)
                    syscall

                    POP_STDCALL_USED_REGS

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
BinShiftTable  db 0,0,2,2,4,4,6,6,8,8,10,10,12,12,14,14,16,16,18,18,20,20,22,22,24,24,26,26,28,28,30,30
OctShiftTable  db 0,0,0,3,3,3,6,6,6,9, 9, 9,12,12,12,15,15,15,18,18,18,21,21,21,24,24,24,27,27,27,30,30
HexShiftTable  db 0,0,0,0,4,4,4,4,8,8,8,8,12,12,12,12,16,16,16,16,20,20,20,20,24,24,24,24,28,28,28,28,32,32,32,32,36,36,36,36,40,40,40,40,44,44,44,44,48,48,48,48,52,52,52,52,56,56,56,56,60,60,60,60,64

printed_symb dq 0

curr_buf_size dq 0

ptr_   db '0x', 0x0
ptrnul db '(nil)', 0x0
strnul db '(null)', 0x0 
nulstr_len equ $ - strnul - 1

buffer  db 10 dup(0)
buf_len equ $ - buffer

section .note.GNU-stack