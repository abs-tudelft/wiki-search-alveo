Alveo build scripts
===================

Description
-----------

This folder contains the build scripts for the Alveo bitstream and the
associated host program/library for interacting with it.

Dependencies
------------

 - Everything in the `hardware` folder (except the simulation itself) should be
   run/generated/checked out.
 - The Python package `vhdeps` must be installed.
 - Apache Arrow must be installed and linkable by the above compiler.
 - A Wikipedia dataset produced with the `data` folder (or post-processed with
   the `optimize` folder) in order to run the host program.
 - There are additional dependencies based on the chosen toolchain.

Usage
-----

Use the appropriate subfolder for the toolchain/runtime version you have.
