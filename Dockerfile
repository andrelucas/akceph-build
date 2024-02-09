FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
	build-essential \
	cmake \
	git \
	jq \
	ninja-build \
	pkg-config \
	sudo

ARG CMAKE_VERSION=v4.9.1
RUN cd /tmp && git clone https://github.com/ccache/ccache.git && cd ccache && \
	git checkout -b ${CMAKE_VERSION} tags/${CMAKE_VERSION} && \
	mkdir build && cd build && \
	cmake -DCMAKE_BUILD_TYPE=Release -DENABLE_TESTING=OFF -DENABLE_DOCUMENTATION=OFF -GNinja .. && \
	ninja install && \
	cd /tmp && rm -rf ccache

ARG PRE_DIR=/tmp/preinstall
RUN mkdir -p ${PRE_DIR} ${PRE_DIR}/debian
COPY preinstall ${PRE_DIR}
WORKDIR ${PRE_DIR}
RUN ./install-deps.sh

ARG CCACHE_LINKS="cc c++ gcc g++ clang clang++"
RUN for p in ${CCACHE_LINKS}; do ln -s /usr/local/bin/ccache /usr/local/bin/$p; done
# If install-deps.sh installed gcc-11 and g++-11, then link them to ccache as
# well. (These are only installed for Ceph >= 18.)
RUN if [ -f /usr/bin/g++-11 ]; then for p in "gcc-11 g++-11"; do ln -s /usr/local/bin/ccache /usr/local/bin/$p; done; fi
ENV CCACHE_DIR=/ccache

ARG TOOLS_DIR=/tools
RUN mkdir -p ${TOOLS_DIR}
COPY tools ${TOOLS_DIR}

WORKDIR /src
ENTRYPOINT ["/tools/source-build.sh"]
