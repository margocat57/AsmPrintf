#include <stdio.h>

/*
nasm -f elf64 -o asm.o printf_start.s
gcc -std=c2x -o program test3.c asm.o
./program
*/

// %d %s %x %d %% %c %b\n, -1, "love", 1802, 100, 33, 126
extern int _printf(const char *format, ...);

int main() {
    int count = 0;

    printf("String ideal: %s\n", NULL);
    _printf("String my: %s\n", NULL);

    _printf("Hex my: %x\n", 1802);
    printf("Hex ideal: %x\n", 1802);

    _printf("b=%b c=%c d=%d o=%o x=%x s=%s p=%p %%\n",
        5, 'A', -42, 511, 48879, "test", "ptr");

    printf("b=%b c=%c d=%d o=%o x=%x s=%s p=%p %%\n",
        5, 'A', -42, 511, 48879, "test", "ptr");

    _printf("Octal my: %o\n", 100);
    printf("Octal ideal: %o\n", 100);

    _printf("Ptr my: %p %p\n", NULL, &count);
    printf("Ptr ideal: %p %p\n", NULL, &count);

    _printf("%d%s%d%s%d%d%d%d%d%d%d%d%c\n", 1, "/", 2, "|", 3, 4, 5, 6, 7, 8, 9, 10, 'a');

    _printf("Decimal my: %d", -2147483648);

    return 0;
}