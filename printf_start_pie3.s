; MY ASSEMBLY PRINTF IMPLEMENTATION
; nasm -f elf64 -o asm.o printf_start_pie3.s  
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
%endmacro

%macro POP_ARGS_REGS 0
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
                    pop qword [rel ret_adress]      ; put return adress(cdecl)

                    PUSH_ARGS_REGS

                    push rbp
                    mov rbp, rsp

                    add rbp, 8           ; rbp = first param
                    call printf_string   ; output string (rdi - pointer to string)

                    call fflush_buffer

                    mov rax, [rel printed_symb]

                    pop rbp

                    POP_ARGS_REGS

                    push qword [rel ret_adress]  ; ret adress
                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Prints string(to buffer or if buffer overflow occured - to stdout)
;
; Entry: rdi --> pointer to string with format specifiers
;        [rbp] - first argument for format specifiers
;
; Exit: does not return anything
;
; Destr: rsi, rdi, r9, rbp, r8, rdx, r11, rcx, rax, r10
;------------------------------------------------------------------
printf_string:      

.output_loop:       cmp byte [rdi], STRING_END
                    je .exit_printf

                    cmp byte [rdi], PERCENT
                    je .percent

                    movzx esi, byte [rdi]
                    call output_char
                    inc rdi
                    jmp .output_loop

.percent:           call process_percent
                    jmp .output_loop

.exit_printf:       ret                                          
;------------------------------------------------------------------


;------------------------------------------------------------------
; Processing format specifiers
;
; Entry: rdi --> pointer to string with format specifiers
;        [rbp] - first argument for format specifiers
;        at stack - arguments for format specifiers
;
; Exit: does not return anything
;
; Destr: rsi, rdi, r9, rbp, r8, rdx, r11, rcx, rax, r10
;------------------------------------------------------------------
process_percent:    inc rdi

                    cmp byte [rdi], PERCENT
                    jne process_spec

incorr_or_percent:  mov esi, PERCENT

                    call output_char
                    jmp exit_switch

process_spec:       movzx esi, byte [rdi] 
                    sub sil, START_SPEC

                    cmp sil, NUM_OF_SPEC
                    ja incorr_or_percent

                    lea r9, [rel FmtSpecTable]     ; r9  = rip + offset FmtSpecTable
                    mov r10, [r9 + 8*rsi]          ; r10 = offset func
                    add r9, r10                    ; r9 = (rip + offset FmtSpecTable)(in r9) + offset func (in r10)
                    jmp r9

binary:             mov esi, dword [rbp]
                    add rbp, 8

                    lea r9, [rel BinShiftTable]  
                    mov ecx, 1
                    call output_bin_hex_oct

                    jmp exit_switch

char:               mov esi, dword [rbp]
                    add rbp, 8 
                    call output_char
                    jmp exit_switch

decimal:            mov esi, dword [rbp] 
                    add rbp, 8
                    call output_decimal
                    jmp exit_switch

octal:              mov esi, dword [rbp]
                    add rbp, 8

                    lea r9, [rel OctShiftTable]  
                    mov ecx, 3
                    call output_bin_hex_oct

                    jmp exit_switch

pointer:            mov rsi, [rbp]
                    add rbp, 8
                    call output_pointer
                    jmp exit_switch

string:             mov rsi, [rbp]
                    add rbp, 8
                    call output_string
                    jmp exit_switch    

hex:                mov esi, dword [rbp]
                    add rbp, 8

                    lea r9, [rel HexShiftTable]  
                    mov ecx, 4
                    call output_bin_hex_oct

                    jmp exit_switch               

exit_switch:        inc rdi
                    ret      
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %b/%x/%o format specifier
;
; Entry:  rsi - argument for format specifier
;         ecx - how many bits we take for conversion at one time
;         r9 ---> pointer to shift table that maps highest set bit index
;               to initial shift (BinShiftTable / OctShiftTable / HexShiftTable)
;
; Exit: does not return anything
;
; Destr: rcx, rsi, r8, rdx, r11, r9
;------------------------------------------------------------------
output_bin_hex_oct: test rsi, rsi
                    jz .is_zero

                    mov r8d, 1
                    shl r8d, cl
                    sub r8d, 1

                    movzx edx, cl 

                    xor ecx, ecx
                    bsr rcx, rsi                  ; старший единичный бит
                    movzx ecx, byte [r9 + rcx]    ; получаем с какого сдвига начнать
                    
                    lea r9, [rel LowHexConvStr]  ; r9 = rip + offset OctConvStr 

.output_loop:       push rsi
                    shr rsi, cl
                    and rsi, r8
                    movzx esi, byte [r9 + rsi]  ; прочитать байт из памяти/регистра и заполнить старшие биты нулями
                    push r9
                    call output_char
                    pop r9

                    pop rsi
                    sub ecx, edx
                    jns .output_loop
                    ret

.is_zero:           mov sil, '0'
                    call output_char
                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %d format specifier
;
; Entry: rsi - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rax, rcx, rdx, rsi, r9, r11
;------------------------------------------------------------------
output_decimal:     test esi, esi          ; SF = 1 if digit < 0
                    jns .process_positive

                    push rsi
                    mov esi, '-'
                    call output_char
                    pop rsi

                    neg esi

.process_positive:  mov r9d, 10
                    mov eax, esi  ; rax = digit
                    xor ecx, ecx  ; rcx = 0 (for symbols count)

.divide_loop:       xor edx, edx
  
                    div r9d     ; частное - rax, остаток rdx

                    add edx, '0'
                    push rdx
                    inc ecx

                    test eax, eax
                    jnz .divide_loop

.output_result:     pop rsi
                    call output_char

                    dec ecx
                    jnz .output_result

.exit:              ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %p format specifier
;
; Entry: rsi - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rcx, rsi, r9, r11, rdx, r8
;------------------------------------------------------------------
output_pointer:     test rsi, rsi
                    jnz .not_zero

                    lea rsi, [rel ptrnul]
                    call output_string
                    ret

.not_zero:          push rsi
                    lea rsi, [rel ptr_]
                    call output_string
                    pop rsi

                    lea r9, [rel HexShiftTable]  
                    mov ecx, 4
                    call output_bin_hex_oct

.exit_output:       ret
;-----------------------------------------------------------------

;------------------------------------------------------------------
; Process %s format specifier
;
; Entry: rsi - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rcx, rsi, r9, r11, r8
;------------------------------------------------------------------
output_string:      test rsi, rsi
                    jnz .not_null

                    lea r8, [rel strnul]
                    mov rcx, nulstr_len
                    jmp .out_str_by_char

.not_null:          mov r8, rsi
                    call my_strlen  ; rcx = num of symb

                    test rcx, rcx
                    jz .exit_output

                    cmp rcx, buf_len - 1
                    jb .out_str_by_char

                    call fflush_buffer
                    call put_str_to_stdout

                    ret
                    
.out_str_by_char:   movzx esi, byte [r8] 
                    call output_char
                    inc r8
                    dec rcx

                    jnz .out_str_by_char

.exit_output:       ret             
;------------------------------------------------------------------

;------------------------------------------------------------------
; Find length of string
;
; Entry: rsi - string
;
; Exit: rcx - length of string
;------------------------------------------------------------------
my_strlen:          xor ecx, ecx

.cmp_loop:          cmp byte [rsi + rcx], 0
                    je .exit
                    inc rcx

                    jmp .cmp_loop

.exit:              ret
;------------------------------------------------------------------


;------------------------------------------------------------------
; Put char to buffer and check buffer overflow (line-buffered)
;
; Entry: sil - char for output
;
; Exit: does not return anything
;
; Destr: r11, r9
;------------------------------------------------------------------
output_char:        mov r11, [rel curr_buf_size]
                    lea r9, [rel buffer]            ; r9 = rip + offset buffer
                    mov byte [r9 + r11], sil
                    inc qword [rel curr_buf_size]

                    cmp sil, 10d
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

section .rodata

align 8
FmtSpecTable:
                                dq binary            -  FmtSpecTable  ; %b
                                dq char              -  FmtSpecTable  ; %c
                                dq decimal           -  FmtSpecTable  ; %d
            times ('o'-'d'-1)   dq incorr_or_percent -  FmtSpecTable
                                dq octal             -  FmtSpecTable  ; %o
                                dq pointer           -  FmtSpecTable  ; %p
            times ('s'-'p'-1)   dq incorr_or_percent -  FmtSpecTable
                                dq string            -  FmtSpecTable  ; %s
            times ('x'-'s'-1)   dq incorr_or_percent -  FmtSpecTable
                                dq hex               -  FmtSpecTable  ; %x

LowHexConvStr  db "0123456789abcdef"
BinShiftTable  db 0,0,2,2,4,4,6,6,8,8,10,10,12,12,14,14,16,16,18,18,20,20,22,22,24,24,26,26,28,28,30,30
OctShiftTable  db 0,0,0,3,3,3,6,6,6,9, 9, 9,12,12,12,15,15,15,18,18,18,21,21,21,24,24,24,27,27,27,30,30
HexShiftTable  db 0,0,0,0,4,4,4,4,8,8,8,8,12,12,12,12,16,16,16,16,20,20,20,20,24,24,24,24,28,28,28,28,32,32,32,32,36,36,36,36,40,40,40,40,44,44,44,44,48,48,48,48,52,52,52,52,56,56,56,56,60,60,60,60,64

ptr_   db '0x', 0x0
ptrnul db '(nil)', 0x0
strnul db '(null)', 0x0 
nulstr_len equ $ - strnul - 1


section .data

printed_symb  dq 0
curr_buf_size dq 0
ret_adress    dq 0

buffer  db 10 dup(0)
buf_len equ $ - buffer

section .note.GNU-stack