# Guest code

This directory contains the code and instructions on how to build the guest
binary image, i.e., the image which is going to be executed on our RISC-V
softcore.

## Prerequisites

You should have a `riscv64-unknown-elf` toolchain installed, e.g., via the
Arch Linux `riscv64-unknown-elf-gcc` AUR package.
Additionally, you'll need picolibc to be installed, e.g., via the
`riscv64-unknown-elf-picolibc` AUR package.

On Ubuntu, the packages `gcc-riscv64-unknown-elf`,
`binutils-riscv64-unknown-elf` and `picolibc-riscv64-unknown-elf` provide the
corresponding prerequisites.

YMMV for other distros.

## Examples

We currently have three examples but adding more is trivial.
These are:

* snake: The classic Snake game. Use `wasd` or `hjkl` for moving the snake.
* tinylisp: A very small LISP REPL.
* mini-rv32ima: A RISC-V emulator that's capable of booting Linux. Who doesn't
  want to run RISC-V on RISC-V?

Build the targets with `make TARGET=<target>` and then use the generated
`mem.vmh` file as memory image for your softcore.
