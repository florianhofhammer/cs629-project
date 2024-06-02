# Softcore implementation

This directory contains the implementation of a RISC-V softcore. One multicycle
core, and two implementations of pipelined ones, as designed during the course
labs. In principle, the work for this project is modular wrt the core itself,
and the design can be swapped out for any other, given that it satisfies the
`RVIfc` interface, and that it recognizes the UART addresses as MMIO (`0xf000000`
and `0xf000005` here).

Check the [top-level README](../README.md) for more info.


## Building

The project is set up akin to `connectal`'s example projects. The build imports
connectal as a submodule, and builds the current project within the `connectal`
repository.

If you have a `mem.vmh` file prepared, pass its path to the make command:

```console
make build.verilator MEM=path/to/mem.vmh
make run.verilator   MEM=path/to/mem.vmh
```

to run a simulation with your file. Omitting the `MEM=` parameter defaults to
using the image from the `guest/` directory in the root of the repository.

Similarly, `build.vcu108`, for example, can be used to build for the FPGA
`VCU108`. The argument is passed directly to `connectal`, where you can check
the list of supported boards.

## Structure

The project is set up to use `Controller.bsv` as the top hardware interface, and
`bridge.cpp` on the software side. The `connectal` \ Bluespec build config is
done inside the `Makefile` in the `proc/` folder. Auxiliary tools for testing,
as well as instructions from the labs have been left mostly untouched, as they
contain instructions to build test examples and a high-level description of the
design itself. 

## Building Connectal

Instructions for dependencies for Connectal can be found in its readme at
[CONNECTAL.md](CONNECTAL.md). We found that using the following (latest at the
time) dependency versions works for us, despite the `connectal` readme pointing
to older versions (package names and exact versions from ArchLinux):

```
bluespec-contrib-git r38.fc26b91-1    // git trunk, 2024-05-30
bluespec-git r834.c481d7f5-1          // git trunk, 2024-05-30
verilator 5.024-1
gmp 6.3.0-2
strace 6.9-1
python-ply 3.11-13
python-gevent 24.2.1-2
// standard C / C++ toolchain
gcc 14.1.1+r58+gfc9fb69ad62-1
gcc-libs 14.1.1+r58+gfc9fb69ad62-1
riscv64-unknown-elf-gcc 13.2.0-2      // for tests and examples
```

Vivado 2019.02 was used to test FPGA builds, but some more work is required to
make things actually work (though for Linux, the amount of memory required is
too high for BRAM, and the addition of a memory controller may be required).
