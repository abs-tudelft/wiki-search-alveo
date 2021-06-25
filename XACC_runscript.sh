
# Start the application
echo "Running the application..."
cd server && \
	LD_LIBRARY_PATH=../alveo:../work/arrow/install/lib:../work/snappy/install/lib \
	./target/release/server ../data/simplewiki-rechunked ../alveo/vitis-2019.2/xclbin/word_match
