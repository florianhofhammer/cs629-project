#include "mmio.h"

/* Set up stdio for picolibc */
static FILE __stdio =
    FDEV_SETUP_STREAM(uart_putchar, uart_getchar, NULL, _FDEV_SETUP_RW);
FILE *const stdin = &__stdio;
__strong_reference(stdin, stdout);
__strong_reference(stdin, stderr);

/* Read a character from UART. */
int uart_getchar(__attribute__((unused)) FILE* file) {
    return *UART_DATA;
}

/* Output a character through the UART. */
int uart_putchar(char c, __attribute__((unused)) FILE* file) {
    *UART_DATA = c;
    return c;
}

/* Check whether a character is available on the UART. */
int uart_available(void) {
    return !!(*UART_STATUS);
}

/* Shut the system down (i.e., exit the simulation) */
__attribute__((noreturn)) void _exit(int c) {
    *SYSTEM_EXIT = c;
    /* System should exit now, the following code should never execute */
    while (1)
        ;
    __builtin_unreachable();
}
