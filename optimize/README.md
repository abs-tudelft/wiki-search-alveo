Record batch optimization tool
==============================

Description
-----------

The tool in this directory takes a set of record batches produced by the Scala
program in the `data` directory, and converts it into another set with
different chunking. Specifically, this tool equally distributes the article
data over N chunks, so each chunk takes approximately the same amount of time
for the hardware to process. Hardware utilization is maximized by setting N to
the number of kernels or an integer multiple thereof.

Dependencies
------------

 - A C++ compiler with C++11 support must be in `$PATH`. If you're using
   something other than `g++`, adjust the command in the makefile.
 - Apache Arrow must be installed and linkable by the above compiler.

Usage
-----

Build using `make`, then run using
`./optimize <input-prefix> <output-prefix> [N]`. N defaults to 15. The prefixes
work by looking for/generating files named `<prefix>-<index>.rb`, where index
ranges from 0 to the number of chunks minus one. The number of input chunks is
auto-detected.
