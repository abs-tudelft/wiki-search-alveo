FROM xilinx/xilinx_runtime_base:alveo-2019.2-ubuntu-18.04

RUN mkdir -p /work

# Install dependency packages
RUN apt-get update && \
    apt install -y -V ca-certificates wget git curl

# Instal GCC 9
RUN apt-get install -y -V gcc-8

# Install latest cmake
RUN mkdir -p /work/cmake && cd /work/cmake && \
    git clone https://github.com/Kitware/CMake.git && \
    mkdir -p install && \
    cd CMake && \
    ./bootstrap --prefix=/work/cmake/install && \
    make -j8 && make install
ENV PATH=$PATH:/work/cmake/install/bin

# Install Apache Arrow
RUN mkdir -p /work/arrow && cd /work/arrow && \
    git clone https://github.com/apache/arrow.git && \
    cd arrow && \
    git checkout apache-arrow-2.0.0 && \
    cd /work/arrow && mkdir build && cd build && \
    cmake ../arrow/cpp && \
    make -j8 && make install

# Install node.js and npm
RUN mkdir -p /work/nodejs && cd /work/nodejs && \
    wget https://nodejs.org/dist/v14.16.1/node-v14.16.1-linux-x64.tar.xz && \
    tar -xJf node-v14.16.1-linux-x64.tar.xz
ENV PATH=$PATH:/work/nodejs/node-v14.16.1-linux-x64/bin

# Install Rust and sbt
RUN mkdir -p /work/rust && cd /work/rust && \
    wget https://sh.rustup.rs -O rustup.sh && \
    sh rustup.sh -y && \
    wget https://github.com/sbt/sbt/releases/download/v1.5.0/sbt-1.5.0.tgz && \
    tar -xzf sbt-1.5.0.tgz
ENV PATH=$PATH:/work/rust/sbt-1.5.0/bin   

# Install Java
# Unfortunately, this way of installing the Oracle JDK doesn't work
#RUN mkdir -p /work/java && cd /work/java && \
#    wget --no-cookies \
#    --no-check-certificate \
#    --header "Cookie: oraclelicense=accept-securebackup-cookie" \
#    http://download.oracle.com/otn-pub/java/jdk/8u151-b12/jdk-8u151-linux-x64.tar.gz \
#    -O jdk-8-linux-x64.tar.gz && \
#    tar -xzf jdk-8-linux-x64.tar.gz
#ENV JAVA_HOME=/work/java/jdk-8-linux-x64
#ENV PATH=$PATH:/work/java/jdk-8-linux-x64/bin
RUN apt-get update && apt-get install -y openjdk-8-jdk
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64/
ENV PATH=$PATH:/usr/lib/jvm/java-8-openjdk-amd64/bin

# Install python3
RUN apt-get -y install python3 python3-pip

RUN pip3 install vhdeps
    
# Download a pre-built Apache Spark
RUN mkdir -p /work/spark && cd /work/spark && \
    wget https://ftp.nluug.nl/internet/apache/spark/spark-3.1.1/spark-3.1.1-bin-hadoop2.7.tgz && \
    tar -xzf spark-3.1.1-bin-hadoop2.7.tgz
ENV PATH=$PATH:/work/spark/spark-3.1.1-bin-hadoop2.7/bin

# Download the app repo
RUN cd /work && \
    git clone --recursive https://github.com/abs-tudelft/wiki-search-alveo /work/wiki-search-alveo

# Build the app client component
RUN cd /work/wiki-search-alveo/client && \
    npm install --unsafe-perm && npm build

# build the host application
RUN bash -c "source /opt/xilinx/xrt/setup.sh && \
    cd /work/wiki-search-alveo/alveo/vitis-2019.2 && \
    XILINX_VITIS=yolo make host"

# build the code to create the dataset
RUN cd /work/wiki-search-alveo/data && \
    sbt package && \
    cd /work/wiki-search-alveo/optimize && \
    make

# build the server
RUN cd /work/wiki-search-alveo/server && \
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

