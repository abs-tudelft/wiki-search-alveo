
To build on qce-alveo01.ewi.tudelft.nl:

 - build hardware with `make all TARGET=hw DEVICE=xilinx_u200_xdma_201830_1` in `alveo`
 - `scl enable devtoolset-7 bash`
 - `export LD_LIBRARY_PATH=/usr/lib64/clang-private:`pwd`/alveo`
 - in `alveo`: `make host` (and maybe run `./host` to verify that it works)
 - on a machine with `npm` and the possibility to install stuff, in `client`: `npm install` followed by `npm run build`
 - in `server`: `cargo build`, then `cargo run` to start serving on port 3030
