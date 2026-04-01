; MY ASSEMBLY PRINTF IMPLEMENTATION
; nasm -f elf64 -o asm7.o printf_start_pie7.s  
; gcc -fsanitize=address -std=c2x -o program7 test3.c asm7.o (sanitizer)
; gcc  -std=c2x -o program6 test3.c asm7.o

; objdump -M intel -d asm6.o | less

STRING_END     equ 0x0
PERCENT        equ '%'
START_SPEC     equ 'b'
NUM_OF_SPEC    equ 'x' - 'b'

%macro PUT_TO_MEM_ARGS_REGS 0
    mov [rel r9_mem], r9 
    mov [rel r8_mem], r8
    mov [rel rcx_mem], rcx
    mov [rel rdx_mem], rdx
    mov [rel rsi_mem], rsi 
    mov [rel rdi_mem], rdi
%endmacro

%macro PUT_TO_ARGS_REGS_MEM 0
    mov r9,  [rel r9_mem]
    mov r8,  [rel r8_mem]
    mov rcx, [rel rcx_mem]
    mov rdx, [rel rdx_mem]
    mov rsi, [rel rsi_mem]
    mov rdi, [rel rdi_mem]
%endmacro

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
extern printf        
extern fflush     

;------------------------------------------------------------------
; Prints string using format specifiers:
; %b, %c, %d, %o, %p, %s, %x
;------------------------------------------------------------------
_printf:            mov qword [rel printed_symb], 0
                    pop qword [rel ret_adress]      ; put return adress(cdecl)

                    ; вызов стандартного printf ----------------------------------------------

                    push r8
                    push rcx

                    lea r8, [rel str_st]
                    mov rcx, str_st_len
                    call put_str_to_stdout

                    pop rcx
                    pop r8

                    PUT_TO_MEM_ARGS_REGS

                    xor eax, eax  ; количество дробных аргументов
                    call printf wrt ..plt ; в pie зарещены прямые ссылки на внешние символы

                    mov rdi, 0        
                    call fflush wrt ..plt    ; если не вызывать будет st: my: 1 2 0x7fff1de1a4541 2 0x7fff1de1a454

                    PUT_TO_ARGS_REGS_MEM 

                    ; ------------------------------------------------------------------------

                    PUSH_ARGS_REGS

                    lea r8, [rel str_my]
                    mov rcx, str_my_len
                    call put_str_to_stdout

                    push rbp
                    mov rbp, rsp

                    xor r10d, r10d
                    sub rsp, 8
                    add rbp, 16           ; rbp = first param
                    call printf_string   ; output string (rdi - pointer to string)

                    call stdcall_put_buffer

                    add rsp, 8

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
; Destr: rsi, rdi, r9, rbp, r8, rdx, r11, rcx, rax
;------------------------------------------------------------------
printf_string:      

.output_loop:       cmp byte [rdi], STRING_END
                    je .exit_printf

                    cmp byte [rdi], PERCENT
                    je .percent

                    movzx edx, byte [rdi]
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
; Destr: rdi, r9, rbp, r8, rdx, r11, rcx, rax
;------------------------------------------------------------------
process_percent:    inc rdi

                    cmp byte [rdi], PERCENT
                    jne .process_spec

.incorr_or_percent: mov edx, PERCENT

                    call output_char
                    jmp .exit_switch

.process_spec:      movzx edx, byte [rdi] 
                    lea r9, [rel FmtSpecTable]         ; r9  = rip + offset FmtSpecTable
                    jmp [r9 + 8*(rdx - 'b')]           ; r9 = (rip + offset FmtSpecTable)(in r9) + offset func (in rsi)

.binary:            mov edx, dword [rbp]
                    add rbp, 8

                    lea r9, [rel BinShiftTable]  
                    mov sil, 1
                    mov ch, 1
                    call output_bin_hex_oct

                    jmp .exit_switch

.char:              mov edx, dword [rbp]
                    add rbp, 8 
                    call output_char
                    jmp .exit_switch

.decimal:           mov edx, dword [rbp] 
                    add rbp, 8
                    call output_decimal
                    jmp .exit_switch

.octal:             mov edx, dword [rbp]
                    add rbp, 8

                    lea r9, [rel OctShiftTable]  
                    mov sil, 3
                    mov ch, 7               
                    call output_bin_hex_oct
                    jmp .exit_switch

.pointer:           mov rdx, [rbp]
                    add rbp, 8
                    call output_pointer
                    jmp .exit_switch

.string:            mov rdx, [rbp]
                    add rbp, 8
                    call output_string
                    jmp .exit_switch    

.hex:               mov edx, dword [rbp]
                    add rbp, 8

                    lea r9, [rel HexShiftTable]  
                    mov sil, 4
                    mov ch, 15
                    call output_bin_hex_oct

                    jmp .exit_switch               

.exit_switch:       inc rdi
                    ret      
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %b/%x/%o format specifier
;
; Entry:  rdx - argument for format specifier
;         sil - how many bits we take for conversion at one time
;         ch  - bit mask
;         r9 ---> pointer to shift table that maps highest set bit index
;               to initial shift (BinShiftTable / OctShiftTable / HexShiftTable)
;
; Exit: does not return anything
;
; Destr: rcx, rsi, rdx, r11, r9, r10
;------------------------------------------------------------------
output_bin_hex_oct: test rdx, rdx
                    jz .is_zero

                    xor r11d, r11d
                    bsr r11, rdx                 ; старший единичный бит
                    mov cl, byte [r9 + r11]      ; получаем с какого сдвига начнать (наименьшее число делящееся на 2^(величина сдвига))
                    
                    lea r11, [rel LowHexConvStr]  ; r11 = rip + offset OctConvStr 

.output_loop:       push rdx

                    shr rdx, cl
                    and dl, ch                
                    movzx edx, dl            

                    movzx edx, byte [r11 + rdx] 
                    call output_char

                    pop rdx
                    sub cl, sil
                    jns .output_loop
                    ret

.is_zero:           mov dl, '0'
                    call output_char
                    ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %d format specifier
;
; Entry: rdx - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rax, rcx, rdx, r9, r11
;------------------------------------------------------------------
output_decimal:     test edx, edx          ; SF = 1 if digit < 0
                    jns .process_positive

                    push rdx
                    mov edx, '-'
                    call output_char
                    pop rdx

                    neg edx

.process_positive:  mov r9d, 10
                    mov eax, edx  ; eax = digit
                    xor ecx, ecx  ; ecx = 0 (for symbols count)

.divide_loop:       xor edx, edx
  
                    div r9d     ; частное - rax, остаток rdx

                    add edx, '0'
                    push rdx
                    inc ecx

                    test eax, eax
                    jnz .divide_loop

.output_result:     pop rdx
                    call output_char

                    dec ecx
                    jnz .output_result

.exit:              ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Process %p format specifier
;
; Entry: rdx - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rcx, rdx, r9, r11, r8
;------------------------------------------------------------------
output_pointer:     test rdx, rdx
                    jnz .not_zero

                    lea rdx, [rel ptrnul]
                    call output_string
                    ret

.not_zero:          push rdx
                    lea rdx, [rel ptr_]
                    call output_string
                    pop rdx

                    lea r9, [rel HexShiftTable]  
                    mov sil, 4
                    mov ch, 15
                    mov rbx, rdx
                    call output_bin_hex_oct

.exit_output:       ret
;-----------------------------------------------------------------

;------------------------------------------------------------------
; Process %s format specifier
;
; Entry: rdx - argument for format specifier
;
; Exit: does not return anything
;
; Destr: rcx, rsi, r9, r11, r8
;------------------------------------------------------------------
output_string:      test rdx, rdx
                    jnz .not_null

                    lea r8, [rel strnul]
                    mov rcx, nulstr_len
                    jmp .out_str_by_char

.not_null:          mov r8, rdx
                    call my_strlen  ; rcx = num of symb

                    test rcx, rcx
                    jz .exit_output

                    cmp rcx, buf_len - 1
                    jb .out_str_by_char

                    call stdcall_put_buffer
                    call put_str_to_stdout

                    ret
                    
.out_str_by_char:   movzx edx, byte [r8] 
                    call output_char
                    inc r8

                    dec rcx
                    jnz .out_str_by_char

.exit_output:       ret             
;------------------------------------------------------------------

;------------------------------------------------------------------
; Find length of string
;
; Entry: rdx - string
;
; Exit: rcx - length of string
;------------------------------------------------------------------
my_strlen:          xor ecx, ecx

.cmp_loop:          cmp byte [rdx + rcx], 0
                    je .exit
                    inc rcx

                    jmp .cmp_loop

.exit:              ret
;------------------------------------------------------------------


;------------------------------------------------------------------
; Put char to buffer and check buffer overflow (line-buffered)
;
; Entry: dl - char for output
;        r10 - current buffer size
;
; Exit:  r10 - increased buffer size
;
; Destr: r10, r9
;------------------------------------------------------------------
output_char:        lea r9, [rel buffer]            ; r9 = rip + offset buffer
                    mov byte [r9 + r10], dl
                    inc r10

                    cmp dl, 10d
                    jne .continue
                    call stdcall_put_buffer

.continue:          cmp r10, buf_len - 1  ; убрать
                    jb .exit_output
                    call stdcall_put_buffer

.exit_output:       ret
;------------------------------------------------------------------

;------------------------------------------------------------------
; Put data of buffer to stdout(using syscall)
;
; Exit: [printed_symb] incremented by number of symbols output to stdout
;       [curr_buf_size] = 0 
;
; Destr: r10
;------------------------------------------------------------------
stdcall_put_buffer: PUSH_STDCALL_USED_REGS

                    mov rax, 0x01      ; write64
                    mov rdi, 1         ; stdout
                    lea rsi, [rel buffer]
                    mov rdx, r10        ; strlen (buffer)
                    syscall

                    POP_STDCALL_USED_REGS

                    add [rel printed_symb], r10
                    mov r10d, 0

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

LowHexConvStr  db "0123456789abcdef"
BinShiftTable  db 0,0,2,2,4,4,6,6,8,8,10,10,12,12,14,14,16,16,18,18,20,20,22,22,24,24,26,26,28,28,30,30
OctShiftTable  db 0,0,0,3,3,3,6,6,6,9, 9, 9,12,12,12,15,15,15,18,18,18,21,21,21,24,24,24,27,27,27,30,30
HexShiftTable  db 0,0,0,0,4,4,4,4,8,8,8,8,12,12,12,12,16,16,16,16,20,20,20,20,24,24,24,24,28,28,28,28,32,32,32,32,36,36,36,36,40,40,40,40,44,44,44,44,48,48,48,48,52,52,52,52,56,56,56,56,60,60,60,60,64

ptr_   db '0x', 0x0
ptrnul db '(nil)', 0x0
strnul db '(null)', 0x0 
nulstr_len equ $ - strnul - 1
str_my db "my: ", 0x0
str_my_len equ $ - str_my
str_st db "st: ", 0x0
str_st_len equ $ - str_st


section .data

align 8
FmtSpecTable:
                                dq process_percent.binary            ; %b
                                dq process_percent.char              ; %c
                                dq process_percent.decimal           ; %d
            times ('o'-'d'-1)   dq process_percent.incorr_or_percent 
                                dq process_percent.octal             ; %o
                                dq process_percent.pointer           ; %p
            times ('s'-'p'-1)   dq process_percent.incorr_or_percent 
                                dq process_percent.string            ; %s
            times ('x'-'s'-1)   dq process_percent.incorr_or_percent 
                                dq process_percent.hex               ; %x

printed_symb  dq 0
ret_adress    dq 0

buffer  db 10 dup(0)
buf_len equ $ - buffer 

rdi_mem       dq 0
rsi_mem       dq 0
rdx_mem       dq 0
rcx_mem       dq 0
r8_mem        dq 0
r9_mem        dq 0

section .note.GNU-stack
; needed because of warning
; /usr/bin/ld: warning: prc2.o: missing .note.GNU-stack section implies executable stack
; /usr/bin/ld: NOTE: This behaviour is deprecated and will be removed in a future version of the linker