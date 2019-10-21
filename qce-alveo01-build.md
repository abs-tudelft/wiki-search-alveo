
To build on qce-alveo01.ewi.tudelft.nl:

 - build hardware with `make all TARGET=hw DEVICE=xilinx_u200_xdma_201830_1` in `alveo`
 - `scl enable devtoolset-7 bash`
 - `export LD_LIBRARY_PATH=/usr/lib64/clang-private:<WORKDIR>/alveo`
 - in `alveo`: `make host` (and maybe run `./host` to verify that it works)
 - in `client`: <<insert dark front-end developer incantations here>> (or copy from `/work/mbrobbel/fletcher-alveo-demo/client/dist`)
 - in `server`: `cargo build`, then `cargo run` to start serving on port 3030
