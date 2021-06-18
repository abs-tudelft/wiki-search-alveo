# Start the application
echo "Running the application..."
cd server && \
	LD_LIBRARY_PATH=../alveo:../work/arrow/install/lib:../work/snappy/install/lib \
	cargo run ../data/simplewiki-rechunked ../alveo/xclbin/word_match

