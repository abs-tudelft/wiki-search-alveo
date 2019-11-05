Fletchgen code generation
=========================

Description
-----------

This folder contains a Python script that can generate the baseline Fletcher
infrastructure for the demo. Note though, that the generated code has undergone
heavy manual optimization to make the demo more space-efficient, so the
generated files are not used by the rest of the demo. Specifically, the bus
widths and toplevel arbiter were hand-optimized to be more narrow than the
default 512-bit width, the `Pages.text` ArrayReader is triplicated for
additional throughput, and the ArrayWriter for `Result.count` is reused for
`Stats.stats`. Ultimately we want to expand Fletchgen to be able to do some of
those things automatically, those things automatically, but it can't do that
yet at the time of writing.

Dependencies
------------

 - `pyarrow` is installed (`pip3 install pyarrow`)
 - `fletcher` is installed (e.g. `pip3 install pyfletcher`) and in `$PATH`.

Usage
-----

Just run `make all` to generate the schema definition files and run `fletchgen`
on them. Run `make clean` to clean the generated files.

You can also run the `generate.py` script directly. Doing so, you can
additionally supply a record batch and a number of rows as argument. This will
then be used to generate an `srec` data file for simulation. While the
generated simulation is also customized, you can quite easily copy a different
data file and the appropriate addresses within the data file over into the
custom simulation toplevel in hardware, in order to run a more advanced
simulation.
