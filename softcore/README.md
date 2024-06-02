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
to older versions:

```
\\ TODO:
```
