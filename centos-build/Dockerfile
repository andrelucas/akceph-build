FROM docker.io/library/rockylinux:8 as deps

# Install the base system, plus everything we'll need to build our custom
# dependencies. We'll reinstall a fresh image later on, you only need the
# packages required to build the custom dependencies, not for building Ceph.
#
# - ccache: libzstd-devel
# - abseil: nothing
# - grpc: openssl-dev (may change later), zlib-devel
# - openssl3: nothing
#

## The dev tools in CentOS 8 and Rocky 8 are called 'powertools'.
RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled powertools

## The dev tools in CentOS Stream 9 and Rocky 9 are called 'crb'
## ('Codeready Builder' in Red Hat terms).
#RUN dnf install -y dnf-plugins-core epel-release && \
#    dnf config-manager --set-enabled crb

# '--allowerasing' is necessary to allow dnf(8) to replace base image versions
# of curl and coreutils with fuller versions.
#
RUN dnf group install --allowerasing -y \
    "Development Tools" && \
    dnf install --allowerasing -y \
    cmake \
    libzstd-devel \
    ninja-build \
    openssl-devel \
    wget \
    zlib-devel

RUN for p in cc c++ gcc g++ clang clang++; do \
    ln -s /usr/local/bin/ccache /usr/local/bin/$p; \
    done

## Populate /build inside the container. These scripts will build custom
## dependencies.
RUN mkdir -p /build
COPY build/ /build/
WORKDIR /build
ENV PATH=/opt/rh/gcc-toolset-11/root/usr/bin:${PATH}
RUN ./ccache.sh
RUN ./golang.sh
RUN ./abseil.sh
RUN ./openssl3.sh
RUN ./grpc.sh

# Main build image. Reinstall base system dependencies, copy custom
# dependencies from the deps image, then clone and build Ceph SRPMS and RPMS.
FROM docker.io/library/rockylinux:8 as build

# Install ccache binary only.
COPY --from=deps /usr/local/bin/ccache /usr/local/bin/ccache
# Install go binaries in /go/bin into /usr/local/bin/.
COPY --from=deps /go/bin/* /usr/local/bin/
# Install dependency libraries and headers to their proper directories.
COPY --from=deps /usr/local/abseil-cpp /usr/local/abseil-cpp
COPY --from=deps /usr/local/go /usr/local/go
COPY --from=deps /usr/local/grpc /usr/local/grpc
COPY --from=deps /usr/local/openssl3 /usr/local/openssl3

RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled powertools
## The dev tools in CentOS Stream 9 and Rocky 9 are called 'crb'
## ('Codeready Builder' in Red Hat terms).
#RUN dnf install -y dnf-plugins-core epel-release && \
#    dnf config-manager --set-enabled crb

# '--allowerasing' is necessary to allow dnf(8) to replace base image versions
# of curl and coreutils with fuller versions.
#
# libstdc++-static is necessary to avoid 'missing libatomic' errors during the
# build.
RUN dnf group install --allowerasing -y \
    "Development Tools" && \
    dnf install --allowerasing -y \
    libstdc++-static \
    wget \
    xxhash-devel

RUN for p in cc c++ gcc g++ clang clang++; do \
    ln -s /usr/local/bin/ccache /usr/local/bin/$p; \
    done

# Install a newer DWZ, in the hope of avoiding annoying crashes. We can't
# (safely) uninstall the RPM dwz because it's a dependency of other things, so
# just nerf it.
ENV DWZ_URI=https://sourceware.org/ftp/dwz/releases DWZ_VER=0.15
RUN mv /usr/bin/dwz /usr/bin/dwz.orig
RUN cd /tmp && \
    mkdir dwz && cd dwz && \
    wget "${DWZ_URI}/dwz-${DWZ_VER}.tar.xz" && \
    wget "${DWZ_URI}/sha512.sum" && \
    sha512sum -c --ignore-missing sha512.sum && \
    tar xJf dwz-${DWZ_VER}.tar.xz && \
    cd dwz && \
    ./configure && make -j$(nproc) && \
    make install && \
    cd / && rm -rf /tmp/dwz

# This will default ccache to /ccache instead of ~/.ccache, and implicitly
# default the config file to /ccache/ccache.conf.
ENV CCACHE_DIR=/ccache

WORKDIR /src

COPY build.sh /build.sh
ENTRYPOINT [ "/build.sh" ]
