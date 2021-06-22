
if [ ! -d $HOME/.cargo ]; then
  echo "Cannot find Rust, please run the build script first."
  exit -1
fi
source $HOME/.cargo/env

# Start the application
echo "Running the application..."
cd server && \
	LD_LIBRARY_PATH=../alveo:../work/arrow/install/lib:../work/snappy/install/lib \
	cargo run ../data/simplewiki-rechunked ../alveo/vitis-2019.2/xclbin/word_match

