#!/bin/bash

# Fetch and build ccache from source.
#
# Requires: cmake, ninja.
# Variables:
# - CCACHE_VERSION: The version of ccache to build.

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "/tmp")
trap 'rm -rf $tmpdir' EXIT

set -e
source config.env

if [[ -z $CCACHE_VERSION ]]; then
    CCACHE_VERSION=4.9.1
fi

set -x
cd "$tmpdir"
git clone https://github.com/ccache/ccache.git
cd ccache
git checkout -b "v${CCACHE_VERSION}" tags/"v${CCACHE_VERSION}"
mkdir build
cd build
env CXXFLAGS="-march=$AKCEPH_GCC_TARGET_ARCH" \
    cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_TESTING=OFF \
    -DENABLE_DOCUMENTATION=OFF \
    -GNinja \
    ..
ninja install
