# Guest code

This directory contains the code and instructions on how to build the guest
binary image, i.e., the image which is going to be executed on our RISC-V
softcore.

## Prerequisites

You should have a `riscv64-unknown-elf` toolchain installed, e.g., via the
Arch Linux `riscv64-unknown-elf-gcc` AUR package.
Additionally, you'll need picolibc to be installed, e.g., via the
`riscv64-unknown-elf-picolibc` AUR package.
