#include <stdio.h>

/*
nasm -f elf64 -o asm.o printf_start.s
gcc -std=c2x -no-pie -o program test3.c asm.o
./program
*/

// %d %s %x %d %% %c %b\n, -1, "love", 1802, 100, 33, 126
extern int _printf(const char *format, ...);

int main() {
    int count = 0;
    
    count = _printf("Hello, World!\n%d%s%x%d%%%c%b\n",  -1, "love", 1802, 100, 33, 126);
    _printf("Returned my: %d\n", count);

    count = printf("Hello, World!\n%d%s%x%d%%%c%b\n", -1, "love", 1802, 100, 33, 126);
    printf("Returned ideal: %d\n", count);

    _printf("Octal my: %o\n", 100);
    printf("Octal ideal: %o\n", 100);

    _printf("Hex my: %x\n", 1802);
    printf("Hex ideal: %x\n", 1802);

    _printf("Ptr my: %p %p\n", NULL, &count);
    printf("Ptr ideal: %p %p\n", NULL, &count);

    _printf("%d%s%d%s%d%d%d%d%d%d%d%d%c\n", 1, "/", 2, "|", 3, 4, 5, 6, 7, 8, 9, 10, 'a');

    _printf("Decimal my: %d", -2147483648);

    return 0;
}