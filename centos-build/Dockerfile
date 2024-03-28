FROM quay.io/centos/centos:stream9 as deps

# Install the base system, plus everything we'll need to build our custom
# dependencies. We'll reinstall a fresh image later on, you only need the
# packages required to build the custom dependencies, not for building Ceph.
#
# - ccache: libzstd-devel
# - abseil: nothing
# - grpc: openssl-dev (may change later), zlib-devel
# - openssl3: nothing
#
RUN dnf install -y epel-release && \
    dnf config-manager --set-enabled crb
# '--allowerasing' is necessary to allow dnf(8) to replace base image versions
# of curl and coreutils with fuller versions.
RUN dnf group install --allowerasing -y \
        "Development Tools" && \
    dnf install --allowerasing -y \
        cmake \
        libzstd-devel \
        ninja-build \
        openssl-devel \
        wget \
        zlib-devel

## Populate /build inside the container. These scripts will build custom
## dependencies.
RUN mkdir -p /build
COPY build/ /build/
WORKDIR /build
RUN ./ccache.sh
RUN ./golang.sh
RUN ./abseil.sh
RUN ./openssl3.sh
RUN ./grpc.sh

# Main build image. Reinstall base system dependencies, copy custom
# dependencies from the deps image, then clone and build Ceph SRPMS and RPMS.
FROM quay.io/centos/centos:stream9 as build

# Install ccache binary only.
COPY --from=deps /usr/local/bin/ccache /usr/local/bin/ccache
# Install go binaries in /go/bin into /usr/local/bin/.
COPY --from=deps /go/bin/* /usr/local/bin/
# Install dependency libraries and headers to their proper directories.
COPY --from=deps /usr/local/abseil-cpp /usr/local/abseil-cpp
COPY --from=deps /usr/local/go /usr/local/go
COPY --from=deps /usr/local/grpc /usr/local/grpc
COPY --from=deps /usr/local/openssl3 /usr/local/openssl3

RUN dnf install -y epel-release && \
    dnf config-manager --set-enabled crb

# '--allowerasing' is necessary to allow dnf(8) to replace base image versions
# of curl and coreutils with fuller versions.
#
# libstdc++-static is necessary to avoid 'missing libatomic' errors during the
# build.
RUN dnf group install --allowerasing -y \
        "Development Tools" && \
    dnf install --allowerasing -y \
        libstdc++-static \
        wget

# This will default ccache to /ccache instead of ~/.ccache, and implicitly
# default the config file to /ccache/ccache.conf.
RUN for p in cc c++ gcc g++ clang clang++; do \
        ln -s /usr/local/bin/ccache /usr/local/bin/$p; \
    done
ENV CCACHE_DIR=/ccache

COPY build.sh /build.sh
ENTRYPOINT [ "/build.sh" ]
