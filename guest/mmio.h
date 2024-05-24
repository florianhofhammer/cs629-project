#ifndef MMIO_H
#define MMIO_H

/* Includes */
#include <stdio.h>
#include <stdint.h>

/* Function prototypes */
int uart_getchar(FILE *file);
int uart_putchar(char c, FILE *file);
int uart_available(void);
void _exit(int c);

/* MMIO addresses */
static volatile int * const UART_BASE = (int *)0xF0000000;
static volatile int * const UART_DATA = UART_BASE;
static volatile int * const UART_STATUS = (int *)((uintptr_t)UART_BASE + 5);
static volatile int * const SYSTEM_EXIT = (int *)0xF000FFF8;
static volatile int * const PUT_ADDR = (int *)0xF000FFF0;
static volatile int * const GET_ADDR = (int *)0xF0000000;
static volatile int * const STATUS_ADDR = (int *)((uintptr_t)GET_ADDR + 5);
static volatile int * const FINISH_ADDR = (int *)0xF000fff8;

#endif /* MMIO_H */
