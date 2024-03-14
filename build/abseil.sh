#!/bin/bash

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "/tmp")
trap 'rm -rf $tmpdir' EXIT

set -e
source config.env

INSTALL_DIR=/usr/local/abseil-cpp

if [[ $AKCEPH_ENABLE_GRPC != 1 ]]; then
    echo "AKCEPH_ENABLE_GRPC is not 1, skipping abseil-cpp build"
    mkdir -p "$INSTALL_DIR" # So the Dockerfile COPY has something to work with.
    exit 0
fi

if [[ -z $ABSEIL_VERSION ]]; then
    ABSEIL_VERSION=20240116.0
fi

if [[ -z $CMAKE_CXX_STANDARD ]]; then
    echo "CMAKE_CXX_STANDARD is not set, defaulting to 17"
    CMAKE_CXX_STANDARD=17
fi

set -x
cd "$tmpdir"
git clone https://github.com/abseil/abseil-cpp.git
cd abseil-cpp
git checkout -b "$ABSEIL_VERSION" "tags/$ABSEIL_VERSION"
mkdir -p build
cd build
env CXX="g++" "CXXFLAGS=-march=$AKCEPH_GCC_TARGET_ARCH" \
    cmake \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
    -DCMAKE_INSTALL_LIBDIR=${INSTALL_DIR}/lib \
    -DCMAKE_CXX_STANDARD="${CMAKE_CXX_STANDARD}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -GNinja \
    ..
ninja install

