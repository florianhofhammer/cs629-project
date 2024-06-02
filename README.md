# CS-629 Final Project

This repository contains our code for the final project for CS-629:
Constructive Computer Architecture @ EPFL.

## Project Goal

In our project, we set the goal to bring Linux up on our softcore.
As this is a quite complex task, we took a small shortcut: instead of bringing
Linux up directly, we boot Linux in a RISC-V emulator running on top of our
RISC-V softcore!

In order to faciliate software development for our softcore, we implemented
two main contributions:

* On the hardware side: implementation of a UART interface that allows for
  communication with the softcore via the command line.
  The goal is to have the same working interface, no matter whether the core
  runs in verilator or on a real FPGA.
  For this purpose, we implement an interface based on the `connectal` project.
* On the software side: implementation of libc support for our softcore and its
  interfaces to be able to run more complex code.
  Notably, this includes formatted I/O which significantly simplifies
  implementation of more complex code (and `printf`-debugging in the process).
  We leverage `picolibc` for this purpose.

## Building and Running Code on the Softcore

The `guest` directory contains the code and instructions on how to build the
guest binary image, i.e., the image which is going to be executed on our RISC-V
softcore.

### Prerequisites

You should have a `riscv64-unknown-elf` toolchain installed, e.g., via the
Arch Linux `riscv64-unknown-elf-gcc` AUR package.
Additionally, you'll need picolibc to be installed, e.g., via the
`riscv64-unknown-elf-picolibc` AUR package.

On Ubuntu, the packages `gcc-riscv64-unknown-elf`,
`binutils-riscv64-unknown-elf` and `picolibc-riscv64-unknown-elf` provide the
corresponding prerequisites.

YMMV for other distros.

### Examples

We currently have three examples in the `guest` directory but adding more is
trivial.
These are:

* `snake`: The classic Snake game. Use `wasd` or `hjkl` for moving the snake.
* `tinylisp`: A very small LISP REPL.
* `mini-rv32ima`: A RISC-V emulator that's capable of booting Linux. Who
  doesn't want to run RISC-V on RISC-V?

Build the targets with `make -C guest TARGET=<target>` and then use the
generated `mem.vmh` file as memory image for your softcore.
