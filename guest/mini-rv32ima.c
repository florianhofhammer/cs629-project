// Copyright 2022 Charles Lohr, you may use this file or any portions herein
// under any of the BSD, MIT, or CC0 licenses.

#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#include "mmio.h"

/* Constants (to be adapted if necessary) */
static int const  time_divisor       = 1;
static bool const single_step        = false;
static bool const fail_on_all_faults = false;

/* RAM */
#define RAM_AMT 64 * 1024 * 1024
static uint8_t ram_image[RAM_AMT] = {0};

/* Kernel image and DTB that get linked in */
extern uint8_t _binary_build_kernel_bin_start;
extern uint8_t _binary_build_kernel_bin_end;
extern uint8_t _binary_build_kernel_bin_size;
extern uint8_t _binary_build_dtb_bin_start;
extern uint8_t _binary_build_dtb_bin_end;
extern uint8_t _binary_build_dtb_bin_size;

static uint32_t HandleException(uint32_t ir, uint32_t retval);
static uint32_t HandleControlStore(uint32_t addy, uint32_t val);
static uint32_t HandleControlLoad(uint32_t addy);
static void HandleOtherCSRWrite(uint8_t *image, uint16_t csrno, uint32_t value);
static int32_t HandleOtherCSRRead(uint8_t *image, uint16_t csrno);
static int     IsKBHit();
static int     ReadKBByte();

#define MINIRV32WARN(...)  printf(__VA_ARGS__);
#define MINIRV32_DECORATE  static
#define MINI_RV32_RAM_SIZE RAM_AMT
#define MINIRV32_IMPLEMENTATION
#define MINIRV32_POSTEXEC(pc, ir, retval)             \
    {                                                 \
        if (retval > 0) {                             \
            if (fail_on_all_faults) {                 \
                printf("FAULT\n");                    \
                return 3;                             \
            } else                                    \
                retval = HandleException(ir, retval); \
        }                                             \
    }
#define MINIRV32_HANDLE_MEM_STORE_CONTROL(addy, val) \
    if (HandleControlStore(addy, val))               \
        return val;
#define MINIRV32_HANDLE_MEM_LOAD_CONTROL(addy, rval) \
    rval = HandleControlLoad(addy);
#define MINIRV32_OTHERCSR_WRITE(csrno, value) \
    HandleOtherCSRWrite(image, csrno, value);
#define MINIRV32_OTHERCSR_READ(csrno, value) \
    value = HandleOtherCSRRead(image, csrno);

#include "mini-rv32ima.h"
static void DumpState(struct MiniRV32IMAState *core, uint8_t *ram_image);

struct MiniRV32IMAState *core;

int main(void) {
    puts("\n\nStarting...\n\n");
restart:
    // Set up kernel image
    memcpy(ram_image, &_binary_build_kernel_bin_start,
           (size_t)&_binary_build_kernel_bin_size);

    // Set up DTB
    int dtb_ptr = RAM_AMT - (size_t)&_binary_build_dtb_bin_size
                  - sizeof(struct MiniRV32IMAState);
    memcpy(ram_image + dtb_ptr, &_binary_build_dtb_bin_start,
           (size_t)&_binary_build_dtb_bin_size);

    // The core lives at the end of RAM.
    core           = (struct MiniRV32IMAState *)(ram_image + RAM_AMT
                                       - sizeof(struct MiniRV32IMAState));
    core->pc       = MINIRV32_RAM_IMAGE_OFFSET;
    core->regs[10] = 0x00;  // hart ID
    core->regs[11] =
        dtb_ptr
            ? (dtb_ptr + MINIRV32_RAM_IMAGE_OFFSET)
            : 0;  // dtb_pa (Must be valid pointer) (Should be pointer to dtb)
    core->extraflags |= 3;  // Machine-mode.

    puts("\n\nKernel img set up, running Linux VM...\n\n");

    // Image is loaded.
    uint64_t rt;
    uint64_t lastTime        = 0;
    int      instrs_per_flip = single_step ? 1 : 1024;
    for (rt = 0;; rt += instrs_per_flip) {
        uint64_t *this_ccount = ((uint64_t *)&core->cyclel);
        uint32_t elapsedUs = elapsedUs = *this_ccount / time_divisor - lastTime;
        lastTime += elapsedUs;

        if (single_step)
            DumpState(core, ram_image);

        int ret = MiniRV32IMAStep(
            core, ram_image, elapsedUs,
            instrs_per_flip);  // Execute upto 1024 cycles before breaking out.
        switch (ret) {
            case 0:
                break;
            case 1:
                *this_ccount += instrs_per_flip;
                break;
            case 0x7777:
                goto restart;  // syscon code for restart
            case 0x5555:
                printf("POWEROFF@0x%08lx%08lx\n", core->cycleh, core->cyclel);
                return 0;  // syscon code for power-off
            default:
                printf("Unknown failure\n");
                break;
        }
    }

    DumpState(core, ram_image);
}

//////////////////////////////////////////////////////////////////////////
// Platform-specific functionality
//////////////////////////////////////////////////////////////////////////

static int ReadKBByte() {
    char rxchar = 0;
    int  rread  = getchar();

    if (rread > 0) {  // Tricky: getchar can't be used with arrow keys.
        return rxchar;
    } else {
        return -1;
    }
}

static int IsKBHit() {
    return uart_available();
}

//////////////////////////////////////////////////////////////////////////
// Rest of functions functionality
//////////////////////////////////////////////////////////////////////////

static uint32_t HandleException(__attribute__((unused)) uint32_t ir,
                                uint32_t                         code) {
    // Weird opcode emitted by duktape on exit.
    if (code == 3) {
        // Could handle other opcodes here.
    }
    return code;
}

static uint32_t HandleControlStore(uint32_t addy, uint32_t val) {
    if (addy == 0x10000000) {  // UART 8250 / 16550 Data Buffer
        printf("%c", (char)val);
    }
    return 0;
}

static uint32_t HandleControlLoad(uint32_t addy) {
    // Emulating a 8250 / 16550 UART
    if (addy == 0x10000005) {
        return 0x60 | IsKBHit();
    } else if (addy == 0x10000000 && IsKBHit())
        return ReadKBByte();
    return 0;
}

static void HandleOtherCSRWrite(__attribute__((unused)) uint8_t *image,
                                uint16_t csrno, uint32_t value) {
    if (csrno == 0x136) {
        printf("%ld", value);
    }
    if (csrno == 0x137) {
        printf("%08lx", value);
    } else if (csrno == 0x138) {
        // Print "string"
        uint32_t ptrstart = value - MINIRV32_RAM_IMAGE_OFFSET;
        uint32_t ptrend   = ptrstart;
        if (ptrstart >= RAM_AMT)
            printf("DEBUG PASSED INVALID PTR (%08lx)\n", value);
        while (ptrend < RAM_AMT) {
            if (image[ptrend] == 0)
                break;
            ptrend++;
        }
        if (ptrend != ptrstart)
            for (uint8_t *c = image + ptrstart; c < image + ptrend; c++) {
                putchar((int)*c);
            }
    } else if (csrno == 0x139) {
        putchar(value);
    }
}

static int32_t HandleOtherCSRRead(__attribute__((unused)) uint8_t *image,
                                  uint16_t                         csrno) {
    if (csrno == 0x140) {
        if (!IsKBHit())
            return -1;
        return ReadKBByte();
    }
    return 0;
}

static void DumpState(struct MiniRV32IMAState *core, uint8_t *ram_image) {
    uint32_t pc        = core->pc;
    uint32_t pc_offset = pc - MINIRV32_RAM_IMAGE_OFFSET;
    uint32_t ir        = 0;

    printf("PC: %08lx ", pc);
    if (pc_offset < RAM_AMT - 3) {
        ir = *((uint32_t *)(&((uint8_t *)ram_image)[pc_offset]));
        printf("[0x%08lx] ", ir);
    } else
        printf("[xxxxxxxxxx] ");
    uint32_t *regs = core->regs;
    printf(
        "Z:%08lx ra:%08lx sp:%08lx gp:%08lx tp:%08lx t0:%08lx t1:%08lx "
        "t2:%08lx "
        "s0:%08lx s1:%08lx a0:%08lx a1:%08lx a2:%08lx a3:%08lx a4:%08lx "
        "a5:%08lx ",
        regs[0], regs[1], regs[2], regs[3], regs[4], regs[5], regs[6], regs[7],
        regs[8], regs[9], regs[10], regs[11], regs[12], regs[13], regs[14],
        regs[15]);
    printf(
        "a6:%08lx a7:%08lx s2:%08lx s3:%08lx s4:%08lx s5:%08lx s6:%08lx "
        "s7:%08lx "
        "s8:%08lx s9:%08lx s10:%08lx s11:%08lx t3:%08lx t4:%08lx t5:%08lx "
        "t6:%08lx\n",
        regs[16], regs[17], regs[18], regs[19], regs[20], regs[21], regs[22],
        regs[23], regs[24], regs[25], regs[26], regs[27], regs[28], regs[29],
        regs[30], regs[31]);
}
