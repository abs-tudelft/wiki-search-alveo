
# Set DEVICE to xilinx_u250 or xilinx_u200, make sure this matches your .xclbin file
DEVICE=xilinx_u250

# simplewiki is a small test dataset, enwiki is the full english wikipedia
DATASET=simplewiki #enwiki

# Change this if you want to use a different parallelization parameter when running Make
NCORES=8

# Find out where the script is located, assume we can create a working dir there
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Let's assume the script is still located in the root of the repo.
# If not, the user also needs to change this here.
repodir=$scriptdir
wdir=$scriptdir/work
mkdir -p $wdir

echo "Script located at $scriptdir, assuming it is still located in the root of the wiki-search-alveo repo. We will install various software dependencies at $wdir. This will consume a fair amount of diskspace. Press enter to continue or Ctrl-C to abort..."
read

# First, check if we happen to be running on the XACC cluster at ETHZ, because we have already set up an environment there.
# Activating it instead of building will save lots of time
env_file="/mnt/scratch/tud-abs/abs-env.sh"
if [ -f $env_file ]; then
  echo "Found TUD ABS environment, activating..."
  source $env_file
fi

# Clone submodules
git submodule init
git submodule update
pushd $repodir/hardware/fletcher
git submodule init
git submodule update
popd

# Install GCC
GCCNAME=gcc-10.3.0
if [ $(g++ -dumpversion | cut -d '.' -f 1) -ge 8 ]; then 
  echo "Found recent enough GCC in PATH, skipping..."
else
  if [ -d $wdir/gcc/install ]; then
    echo "GCC seems to be installed already, skipping..."
  else
    echo "This demo needs C++17 features that are available from GCC version 8 and above.
your GCC version seems to be too old. If possible, install a newer version or enable a toolset.
otherwise, the script will now attempt to build GCC 10 from source (which will consume lots of time and disk space.
Press enter to continue or Ctrl-C to abort..."
    read
    mkdir -p $wdir/gcc && cd $wdir/gcc && \
    wget https://ftp.gnu.org/gnu/gcc/${GCCNAME}/${GCCNAME}.tar.gz && \
    tar -xzf ${GCCNAME}.tar.gz && \
    cd $wdir/gcc/${GCCNAME} && ./contrib/download_prerequisites && \
    mkdir -p $wdir/gcc/build && cd $wdir/gcc/build && \
    $wdir/gcc/${GCCNAME}/configure --prefix=$wdir/gcc/install --disable-multilib && \
    make -j${NCORES} && make install
    if [ $? != 0 ]; then
      echo "Something went wrong during GCC installation, exiting"
    exit -1
    fi
  fi
  export PATH=$wdir/gcc/install/bin:$PATH
  export LD_LIBRARY_PATH=$wdir/gcc/install/lib64:$wdir/gcc/install/lib:$LD_LIBRARY_PATH
fi

# Install CMake
if cmake --version && [ $(cmake --version | head -n 1 | cut -d . -f 2) -ge 10 ]; then
  echo "Found recent enough CMake version in PATH, skipping..."
elif [ -d $wdir/cmake/install ]; then
  echo "CMake seems to be installed already, skipping..."
else
echo "Installing CMake..."
mkdir -p $wdir/cmake && cd $wdir/cmake && \
git clone https://github.com/KitWare/CMake && \
cd CMake && \
git checkout v3.20.5 && \
./bootstrap --prefix=$wdir/cmake/install && \
make -j${NCORES} && make install
fi
if [ $? != 0 ]; then
  echo "Something went wrong during CMake installation, exiting"
  exit -1
fi
export PATH=$wdir/cmake/install/bin:$PATH

# Install Apache Arrow
if pkg-config arrow && [ $(pkg-config --modversion arrow | cut -d . -f 1) -ge 3 ]; then
  echo "Found recent enough Apache Arrow package, skipping..."	
elif [ -d $wdir/arrow/install ]; then
  echo "Apache Arrow seems to be installed already, skipping..."
else
echo "Installing Apache Arrow..."
mkdir -p $wdir/arrow && cd $wdir/arrow && \
git clone https://github.com/apache/arrow.git && \
cd arrow && \
git checkout apache-arrow-3.0.0 && \
cd $wdir/arrow && mkdir build && cd build && \
CFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" CXXFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" LDFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0"  cmake -DCMAKE_INSTALL_PREFIX:PATH=$wdir/arrow/install ../arrow/cpp && \
make -j${NCORES} && make install
fi
if [ $? != 0 ]; then
  echo "Something went wrong during Apache Arrow 2.0 installation, exiting"
  exit -1
fi
arrow_libdir=$wdir/arrow/install/$(ls $wdir/arrow/install | grep lib) #some systems have a lib dir, other a lib64...

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

export PATH=$wdir/nodejs/node-v14.16.1-linux-x64/bin:$PATH


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
export PATH=$wdir/sbt/sbt/bin:$PATH


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
#export PATH=$wdir/java/jdk-8-linux-x64/bin:$PATH


#Let's hope the default java 11 will suffice
#RUN apt-get update && apt-get install -y openjdk-8-jdk
#export JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64/
#export PATH=/usr/lib/jvm/java-8-openjdk-amd64/bin:$PATH

# Install vhdeps
pip3 install vhdeps

# Download a pre-built Apache Spark
#if [ -d $wdir/spark/spark-3.1.1-bin-hadoop2.7/bin ]; then
if [ -d $wdir/spark/spark-2.4.8-bin-hadoop2.7/bin ]; then
  echo "Apache Spark seems to be downloaded already, skipping..."
else
echo "Downloading a pre-built Apache Spark"
mkdir -p $wdir/spark && cd $wdir/spark && \
wget https://ftp.nluug.nl/internet/apache/spark/spark-2.4.8/spark-2.4.8-bin-hadoop2.7.tgz && \
tar -xzf spark-2.4.8-bin-hadoop2.7.tgz
fi
if [ $? != 0 ]; then
  echo "Something went wrong during Apache Spark installation, exiting"
  exit -1
fi
export PATH=$wdir/spark/spark-2.4.8-bin-hadoop2.7/bin:$PATH
#wget https://ftp.nluug.nl/internet/apache/spark/spark-3.1.1/spark-3.1.1-bin-hadoop2.7.tgz && \

# Install snappy decompressor (software)
if [ -d $wdir/snappy/install ]; then
  echo "Snappy seems to be installed already, skipping..."
else
mkdir -p $wdir/snappy && cd $wdir/snappy
git clone https://github.com/google/snappy
pushd snappy
git checkout 1.1.8 # Shared library building doesn't work for latest (1.1.9) version
git submodule update --init
popd
mkdir -p $wdir/snappy/build && cd $wdir/snappy/build
cmake -DCMAKE_INSTALL_PREFIX:PATH=$wdir/snappy/install \
-DCMAKE_BUILD_TYPE=release -DBUILD_SHARED_LIBS=On -DSNAPPY_BUILD_TESTS=Off ../snappy
make
make install
fi
if [ $? != 0 ]; then
  echo "Something went wrong during Snappy installation, exiting"
  exit -1
fi
snappy_libdir=$wdir/snappy/install/$(ls $wdir/snappy/install | grep lib) #some systems have a lib dir, other a lib64...

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
if [ -f $repodir/alveo/vitis-2019.2/host ]; then
  echo "Host application seems to be built already. Skipping..."
else
echo "Building the wiki-search host code"
bash -c "source /opt/xilinx/xrt/setup.sh && \
cd $repodir/alveo/vitis-2019.2 && \
PKG_CONFIG_PATH=$wdir/arrow/build/src/arrow \
LD_LIBRARY_PATH=$snappy_libdir:$LD_LIBRARY_PATH \
make host DEVICE=$DEVICE" 
#Xilinx build files want this to be defined, but it is not used
if [ $? != 0 ]; then
  echo "Something went wrong during wiki-search host code building, exiting"
  exit -1
fi
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
LD_LIBRARY_PATH=$repodir/alveo:$arrow_libdir:$snappy_libdir:$LD_LIBRARY_PATH \
cargo build --release
if [ $? != 0 ]; then
  echo "Something went wrong during server code building, exiting"
  exit -1
# If your machine cannot find some clang AST library, try adding LD_LIBRARY_PATH=/usr/lib64/clang-private
fi


# Create an example dataset
if [ -f $repodir/data/${DATASET}-rechunked-0.rb ]; then
echo "An existing example dataset has been found. Skipping creation..."
else
echo "Creating an example dataset"
cd $repodir/data
if [ ! -f ${DATASET}-latest-pages-articles-multistream.xml.bz2 ]; then
  wget https://dumps.wikimedia.org/${DATASET}/latest/${DATASET}-latest-pages-articles-multistream.xml.bz2
fi
spark-submit \
--conf "spark.driver.extraJavaOptions=-Djava.net.useSystemProxies=true" \
--packages com.databricks:spark-xml_2.11:0.6.0 \
target/scala-2.11/wikipedia-to-arrow-with-snappy_2.11-1.0.jar \
${DATASET}-latest-pages-articles-multistream.xml.bz2 ${DATASET}
if [ $? != 0 ]; then
  echo "Something went wrong during dataset creation, exiting"
  exit -1
fi
cd $repodir/data && \
LD_LIBRARY_PATH=$arrow_libdir:LD_LIBRARY_PATH ../optimize/optimize ${DATASET} ${DATASET}-rechunked
if [ $? != 0 ]; then
  echo "Something went wrong during dataset optimization, exiting"
  exit -1
fi
fi

echo "Finished building wiki-search example. Start the application using the run script.\n\n"
exit 0
