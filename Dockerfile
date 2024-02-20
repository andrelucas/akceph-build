FROM ubuntu:20.04 as deps

# Install the base system, plus everything we'll need to build our custom
# dependencies.
# - ccache: libzstd-dev
# - abseil: nothing
# - grpc: libssl-dev (may change later), zlib1g-dev
# - openssl3: nothing
#
RUN apt-get update && env DEBIAN_FRONTEND=noninteractive apt-get install -y \
	build-essential \
	cmake \
	curl \
	git \
	libssl-dev \
	libzstd-dev \
	ninja-build \
	pkg-config \
	zlib1g-dev

## Populate /build inside the container. These scripts will build custom
## dependencies.
RUN mkdir -p /build
COPY build/ /build/
WORKDIR /build
RUN ./ccache-bin.sh
RUN ./golang.sh
RUN ./abseil.sh
RUN ./openssl3.sh
RUN ./grpc.sh

FROM ubuntu:20.04 as build

# Install ccache binary only.
COPY --from=deps /usr/local/bin/ccache /usr/local/bin/ccache
# Install go binaries in /go/bin into /usr/local/bin/.
COPY --from=deps /go/bin/* /usr/local/bin/
# Install dependency libraries and headers to their proper directories.
COPY --from=deps /usr/local/abseil-cpp /usr/local/abseil-cpp
COPY --from=deps /usr/local/go /usr/local/go
COPY --from=deps /usr/local/grpc /usr/local/grpc
COPY --from=deps /usr/local/openssl3 /usr/local/openssl3

# Install the base system, plus everything we'll need to build and run Ceph.
# Don't forget to include things the custom dependencies need on, or they'll
# either fail to link or fail to run.
#
RUN apt-get update && env DEBIAN_FRONTEND=noninteractive apt-get install -y \
	build-essential \
	cmake \
	curl \
	doxygen \
	git \
	jq \
	libssl-dev \
	libzstd-dev \
	net-tools \
	netcat-openbsd \
	ninja-build \
	pkg-config \
	python3-pip \
	sudo \
	vim \
	zlib1g-dev

# Install python modules required for vstart.sh.
RUN pip3 install \
	bcrypt \
	python-dateutil \
	jwt \
	prettytable \
	pyOpenSSL

## Unset compiler variables after building custom dependencies.
ENV CC= CFLAGS=
ENV CXX= CXXFLAGS=

ARG PRE_DIR=/tmp/preinstall
RUN mkdir -p ${PRE_DIR} ${PRE_DIR}/debian
COPY preinstall ${PRE_DIR}
WORKDIR ${PRE_DIR}
RUN ./install-deps.sh

ARG CCACHE_LINKS="cc c++ gcc g++ clang clang++"
RUN for p in ${CCACHE_LINKS}; do ln -s /usr/local/bin/ccache /usr/local/bin/$p; done
# If install-deps.sh installed gcc-11 and g++-11, then link them to ccache as
# well. (These are only installed for Ceph >= 18.)
RUN if [ -f /usr/bin/g++-11 ]; then for p in gcc-11 g++-11; do ln -s /usr/local/bin/ccache /usr/local/bin/$p; done; fi
ENV CCACHE_DIR=/ccache

ARG TOOLS_DIR=/tools
RUN mkdir -p ${TOOLS_DIR}
COPY tools ${TOOLS_DIR}

# More informative Ninja status output by default.
ENV NINJA_STATUS="[%p :: t=%t/f=%f/r=%r :: %e] "

# Stop git whinging about source directories.
RUN git config --global --add safe.directory "*"
# BUG: ./run-make-check.sh fails if these are empty. (When building python
# BUG: module xmlsec.)
ENV CC=gcc CXX=g++

WORKDIR /src
ENTRYPOINT ["/tools/source-build.sh"]
