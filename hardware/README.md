Hardware
========

Description
-----------

This folder contains the kernel and (modified) Fletcher wrapper.

Dependencies
------------

 - The [Fletcher](https://github.com/abs-tudelft/fletcher),
   [vhlib](https://github.com/abs-tudelft/vhlib) and
   [vhsnunzip](https://github.com/abs-tudelft/vhsnunzip) submodules are checked
   out appropriately (`git submodule update --init --recursive`).
 - The Python packages `vhdmmio` and `vhdeps` must be installed.
 - Either `ghdl` or a Modelsim-compatible simulator must be installed and in
   `$PATH` to run the simulation.

Usage
-----

Run `run-vhdmmio.sh` to generate the SDAccel-compatible register file for the
demo. You have to do this before you can simulate or synthesize.

To simulate a very basic test case, run
`run-vhdeps.sh [ghdl|vsim] WordMatch_SimTop_tc`. Note that this test case is
not self-checking though; if you want to simulate, you should try to understand
the test case and register file so you can modify it to change the test. The
test case uses `vhdl/memory.srec` as its data source, which by default contains
just three very short "articles".
