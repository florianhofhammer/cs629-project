Connectal for the CCA Project
=============================

Everything we work on is in `examples/proc_multi`. The test can be built by
replacing the `mem.vmh` file inside the `examples/proc_multi/verilator` folder,
and running 

```console
make build.verilator
make run.verilator
```

in the `examples/proc_multi` folder. This also generates most things inside the
`verilator` folder. 

The project is set up to use `Controller.bsv` as the top hardware interface, and
`bridge.cpp` on the software side. The config is done inside the `Makefile`
itself. 

Instructions for dependencies for Connectal can be found in its readme at
[CONNECTAL.md](CONNECTAL.md).
