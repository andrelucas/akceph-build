FROM ubuntu:20.04

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
	jq \
	libssl-dev \
	libzstd-dev \
	ninja-build \
	pkg-config \
	sudo \
	vim \
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

WORKDIR /src
ENTRYPOINT ["/tools/source-build.sh"]
