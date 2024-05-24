#include "mmio.h"

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
