#include <stdio.h>

/*
nasm -f elf64 -o asm.o printf_start.s
gcc -std=c2x -no-pie -o program test.c asm.o
./program
*/

extern int _printf(const char *format, ...);

int main() {
    int count = 0;
    
    count = _printf("Hello, World!\n");
    printf("Returned: %d\n", count);
    
    int ret = _printf("%d %s %x %d%%%c%b %d %c %x\n", -1, "love", 3802, 100, 33, 127, 57, 63, 64);
    // -1 love 0xeda 100%!0b1111111
    _printf("Number: %d\n", 42);
    _printf("Hex: %x\n", 123);
    printf("Hex: %x\n", 123);
    _printf("Binary: %b\n", 127);
    printf("Binary: %b\n", 127);
    _printf("Octal: %o\n", 123);
    printf("Octal: %o\n", 123);
    _printf("String: %s\n", "test");
    _printf("Char: %c\n", 'A');
    
    _printf("Values: %d %x %s\n", 100, 0xFF, "done");
    printf("Values: %d %x %s\n", 100, 0xFF, "done");
    
    int x = 10;
    _printf("Pointer: %p\n", &x);
    printf("Pointer: %p\n", &x);
    
    _printf("Percent: %%\n");
    
    return 0;
}