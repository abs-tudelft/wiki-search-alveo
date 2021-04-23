FROM xilinx/xilinx_runtime_base:alveo-2019.2-ubuntu-18.04

# Install dependency packages
RUN apt-get update && \
    apt install -y -V ca-certificates wget git curl
    
# Install latest cmake
RUN mkdir -p /cmake && cd /cmake && \
    git clone https://github.com/Kitware/CMake.git && \
    mkdir -p install && \
    cd CMake && \
    ./bootstrap --prefix=/cmake/install && \
    make -j8 && make install

# Install Apache Arrow
RUN mkdir -p /arrow && cd /arrow && \
    git clone https://github.com/apache/arrow.git && \
    cd arrow && \
    git checkout apache-arrow-2.0.0 && \
    cd /arrow && mkdir build && cd build && \
    cmake ../arrow/cpp && \
    make -j8 && make install

# Install node.js and npm
RUN mkdir -p /nodejs && cd /nodejs && \
    wget https://nodejs.org/dist/v14.16.1/node-v14.16.1-linux-x64.tar.xz && \
    tar -xJf node-v14.16.1-linux-x64.tar.xz
ENV PATH=$PATH:/nodejs/node-v14.16.1-linux-x64/bin

# Install Rust and sbt
RUN mkdir -p /rust && cd /rust && \
    wget https://sh.rustup.rs -O rustup.sh && \
    sh rustup.sh -y && \
    wget https://github.com/sbt/sbt/releases/download/v1.5.0/sbt-1.5.0.tgz && \
    tar -xzf sbt-1.5.0.tgz
ENV PATH=$PATH:/rust/sbt-1.5.0/bin   

# Install Java
RUN mkdir -p /java && cd /java && \
    wget --no-cookies \
    --no-check-certificate \
    --header "Cookie: oraclelicense=accept-securebackup-cookie" \
    http://download.oracle.com/otn-pub/java/jdk/8u151-b12/jdk-8u151-linux-x64.tar.gz \
    -O jdk-8-linux-x64.tar.gz && \
    tar -xzf jdk-8-linux-x64.tar.gz
ENV JAVA_HOME=/java/jdk-8-linux-x64
ENV PATH=$PATH:/java/jdk-8-linux-x64/bin

RUN pip install vhdeps
    
# Download a pre-built Apache Spark
RUN mkdir -p /spark && \
    cd /spark && \
    wget https://ftp.nluug.nl/internet/apache/spark/spark-3.1.1/spark-3.1.1-bin-hadoop2.7.tgz && \
    tar -xzf spark-3.1.1-bin-hadoop2.7.tgz

ENV PATH=$PATH:/spark/spark-3.1.1-bin-hadoop2.7/bin

# Download the app repo
RUN mkdir -p /work && \
    git clone --recursive https://github.com/abs-tudelft/wiki-search-alveo /work/wiki-search-alveo

# Build the app components
RUN cd /work/wiki-search-alveo/client && \
    /usr/local/bin/npm install && /usr/local/bin/npm build && \
    cd /work/wiki-search-alveo/alveo && \
    make host && \
    cd /work/wiki-search-alveo/data && \
    sbt package && \
    cd /work/wiki-search-alveo/optimize && \
    make && \
    cd /work/wiki-search-alveo/server && \
    LD_LIBRARY_PATH=`pwd`/../alveo \
    cargo build
    
# Create an example dataset
RUN cd /work/wiki-search-alveo/data && \
    wget https://dumps.wikimedia.org/simplewiki/latest/simplewiki-latest-pages-articles-multistream.xml.bz2 && \
    spark-submit \
    --packages com.databricks:spark-xml_2.11:0.6.0 \
    target/scala-2.11/wikipedia-to-arrow-with-snappy_2.11-1.0.jar \
    simplewiki-latest-pages-articles-multistream.xml.bz2 simplewiki && \
    cd /work/wiki-search-alveo/data && \
    ../optimize/optimize simplewiki simplewiki-rechunked

# Copy the pre-synthesized bitstream for the U250
COPY u250/xclbin /work/wiki-search-alveo/alveo/vitis-2019.2/

# Start the application
RUN cd /work/wiki-search-alveo/server && \
    LD_LIBRARY_PATH=`pwd`/../alveo \
    cargo run ../data/simplewiki-rechunked ../alveo/xclbin/word_match

WORKDIR /work

