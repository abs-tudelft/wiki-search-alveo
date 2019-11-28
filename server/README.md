Web server code
===============

Description
-----------

This folder contains the sources for the Rust webserver based on Warp, serving
the web application frontend in the `client` folder.

Dependencies
------------

 - Rust stable.
 - The host library and bitstream must be built using the `alveo` directory.
 - Clang, used to generate the Rust bindings from the C header file.
 - The `LD_LIBRARY_PATH` environment variable must be pointed to the `alveo`
   directory, in order to let the server find the host library.
 - A Wikipedia dataset produced with the `data` folder (or post-processed with
   the `optimize` folder) in order to run the host program.
 - The client sources must be built in the `client` folder.
 - Port 3030 is used to run the server, so it must be free.

Usage
-----

Run the demo using

```
LD_LIBRARY_PATH=`pwd`/../alveo \
    cargo run [--release] <dataset-prefix> [../alveo/xclbin/word_match]
```

The latter parameter is optional; if omitted, the demo is run in software-only mode,
without claiming a Xilinx OpenCL context.

The server will start listening to HTTP requests on port 3030 after it finishes
loading the dataset. You can stop the server by pressing Ctrl+C.
