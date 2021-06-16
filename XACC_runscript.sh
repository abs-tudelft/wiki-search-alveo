# Find out where the script is located, assume we can create a working dir there
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Let's assume the script is still located in the root of the repo.
# If not, the user also needs to change this here.
repodir=$scriptdir
wdir=$scriptdir/work
mkdir -p $wdir
cd $wdir

# Clone submodules
git submodule init
git submodule update
pushd $repodir/hardware/fletcher
git submodule init
git submodule update
popd

echo "Script located at $scriptdir, assuming it is still located in the root of the wiki-search-alveo repo. We will install various software dependencies at $wdir. This will consume a fair amount of diskspace. Press enter to continue or Ctrl-C to abort..."
read

# Activate an environment with recent GCC, CMake, python
echo "Activating /mnt/scratch/tud-abs Conda environment"
source /mnt/scratch/tud-abs/abs-env.sh

# Install Apache Arrow
if [ -d $wdir/arrow/install/lib ]; then
  echo "Apache Arrow seems to be installed already, skipping..."
else
echo "Installing Apache Arrow 2.0..."
mkdir -p $wdir/arrow && cd $wdir/arrow && \
git clone https://github.com/apache/arrow.git && \
cd arrow && \
git checkout apache-arrow-3.0.0 && \
cd $wdir/arrow && mkdir build && cd build && \
CFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" CXXFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" LDFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0"  cmake -DCMAKE_INSTALL_PREFIX:PATH=$wdir/arrow/install ../arrow/cpp && \
make -j8 && \
mkdir -p $wdir/arrow/install && \
make install
fi
if [ $? != 0 ]; then
  echo "Something went wrong during Apache Arrow 2.0 installation, exiting"
  exit -1
fi

# Install node.js and npm
if [ -d $wdir/nodejs/node-v14.16.1-linux-x64/bin ]; then
  echo "node.js seems to be installed already, skipping..."
else
echo "Downloading and installing node.js..."
mkdir -p $wdir/nodejs && cd $wdir/nodejs && \
wget https://nodejs.org/dist/v14.16.1/node-v14.16.1-linux-x64.tar.xz && \
tar -xJf node-v14.16.1-linux-x64.tar.xz
fi
if [ $? != 0 ]; then
  echo "Something went wrong during node.js installation, exiting"
  exit -1
fi

export PATH=$PATH:$wdir/nodejs/node-v14.16.1-linux-x64/bin


# Install Rust
if [ -d $HOME/.cargo ]; then
  echo "Rust seems to be installed already, skipping..."
else
echo "Downloading and installing Rust..."
mkdir -p $wdir/rust && cd $wdir/rust && \
wget https://sh.rustup.rs -O rustup.sh && \
sh rustup.sh -y
fi
if [ $? != 0 ]; then
  echo "Something went wrong during Rust installation, exiting"
  exit -1
fi
source $HOME/.cargo/env

# Install Scala SBT
if [ -d $wdir/sbt/sbt ]; then
  echo "Scala SBT seems to be installed already, skipping..."
else
mkdir -p $wdir/sbt && cd $wdir/sbt && \
wget https://github.com/sbt/sbt/releases/download/v1.5.0/sbt-1.5.0.tgz && \
tar -xzf sbt-1.5.0.tgz
fi
if [ $? != 0 ]; then
  echo "Something went wrong during Scala SBT installation, exiting"
  exit -1
fi
export PATH=$PATH:$wdir/sbt/sbt/bin


# Install Java
# Unfortunately, this way of installing the Oracle JDK doesn't work
#mkdir -p $wdir/java && cd $wdir/java && \
#wget --no-cookies \
#--no-check-certificate \
#--header "Cookie: oraclelicense=accept-securebackup-cookie" \
#http://download.oracle.com/otn-pub/java/jdk/8u151-b12/jdk-8u151-linux-x64.tar.gz \
#-O jdk-8-linux-x64.tar.gz && \
#tar -xzf jdk-8-linux-x64.tar.gz
#export JAVA_HOME=$wdir/java/jdk-8-linux-x64
#export PATH=$PATH:$wdir/java/jdk-8-linux-x64/bin


#Let's hope the default java 11 will suffice
#RUN apt-get update && apt-get install -y openjdk-8-jdk
#export JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64/
#export PATH=$PATH:/usr/lib/jvm/java-8-openjdk-amd64/bin

# Install vhdeps
pip3 install vhdeps

# Download a pre-built Apache Spark
if [ -d $wdir/spark/spark-3.1.1-bin-hadoop2.7/bin ]; then
  echo "Apache Spark seems to be downloaded already, skipping..."
else
echo "Downloading a pre-built Apache Spark"
mkdir -p $wdir/spark && cd $wdir/spark && \
wget https://ftp.nluug.nl/internet/apache/spark/spark-3.1.1/spark-3.1.1-bin-hadoop2.7.tgz && \
tar -xzf spark-3.1.1-bin-hadoop2.7.tgz
fi
if [ $? != 0 ]; then
  echo "Something went wrong during Apache Spark installation, exiting"
  exit -1
fi
export PATH=$PATH:$wdir/spark/spark-3.1.1-bin-hadoop2.7/bin

# Install snappy decompressor (software)
if [ -d $wdir/snappy/install ]; then
  echo "Snappy seems to be downloaded already, skipping..."
else
mkdir -p $wdir/snappy && cd $wdir/snappy
git clone https://github.com/google/snappy
pushd snappy
git submodule update --init
popd
mkdir -p $wdir/snappy/build && cd $wdir/snappy/build
cmake -DCMAKE_INSTALL_PREFIX:PATH=$wdir/snappy/install ../snappy
make
make install
fi
if [ $? != 0 ]; then
  echo "Something went wrong during Snappy Spark installation, exiting"
  exit -1
fi


echo "Finished Building the prerequisites. Now continuing with the wiki-search application..."

# Build the app client component
echo "Building the wiki-search client"
cd $repodir/client && \
npm install --unsafe-perm && npm run build
if [ $? != 0 ]; then
  echo "Something went wrong during wiki-search client building, exiting"
  exit -1
fi


# build the host application
echo "Building the wiki-search host code"
bash -c "source /opt/xilinx/xrt/setup.sh && \
cd $repodir/alveo/vitis-2019.2 && \
XILINX_VITIS=yolo \ 
PKG_CONFIG_PATH=$wdir/arrow/build/src/arrow \
make host" 
#Xilinx build files want this to be defined, but it is not used
if [ $? != 0 ]; then
  echo "Something went wrong during wiki-search host code building, exiting"
  exit -1
fi


# build the code to create the dataset
echo "Building the dataset creation utilities"
cd $repodir/data && \
sbt package && \
cd $repodir/optimize && \
make
if [ $? != 0 ]; then
  echo "Something went wrong during dataset creation code building, exiting"
  exit -1
fi


# build the server
echo "Building the server code"
cd $repodir/server && \
LD_LIBRARY_PATH=`pwd`/../alveo \
cargo build
if [ $? != 0 ]; then
  echo "Something went wrong during server code building, exiting"
  exit -1
fi


# Create an example dataset
echo "Creating an example dataset"
cd $repodir/data
if [ ! -f simplewiki-latest-pages-articles-multistream.xml.bz2 ]; then
  wget https://dumps.wikimedia.org/simplewiki/latest/simplewiki-latest-pages-articles-multistream.xml.bz2
fi
spark-submit \
--packages com.databricks:spark-xml_2.11:0.6.0 \
target/scala-2.11/wikipedia-to-arrow-with-snappy_2.11-1.0.jar \
simplewiki-latest-pages-articles-multistream.xml.bz2 simplewiki
if [ $? != 0 ]; then
  echo "Something went wrong during dataset creation, exiting"
  exit -1
fi
cd $repodir/data && \
../optimize/optimize simplewiki simplewiki-rechunked
if [ $? != 0 ]; then
  echo "Something went wrong during dataset optimization, exiting"
  exit -1
fi


if [ ! -d $repodir/alveo/vitis-2019.2/xclbin ]; then
  echo "Error: Please make sure there is a bitstream available in alveo/vitis-2019.2/xclbin"
  exit -1
fi

# Start the application
echo "Running the application..."
cd $repodir/server && \
LD_LIBRARY_PATH=`pwd`/../alveo \
cargo run ../data/simplewiki-rechunked ../alveo/xclbin/word_match

