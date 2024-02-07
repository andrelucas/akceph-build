#!/bin/bash

set -e
cd /src

# Without this git(1) will object to the directory being owned by a different
# user. The wildcard means it applies to submodules as well.
git config --global --add safe.directory "*"

export NINJA_STATUS="[%p :: t=%t/f=%f/r=%r :: %e] "

BUILD_TYPE="${BUILD_TYPE:-Debug}"
export BUILD_TYPE

BUILD_NPROC="${BUILD_NPROC:-$(nproc)}"
export BUILD_NPROC

export BUILD_DIR=build.$BUILD_TYPE

rm -rf "$BUILD_DIR"

./do_cmake.sh -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DALLOCATOR=tcmalloc \
    -DBOOST_J="$BUILD_NPROC" \
    -DWITH_CCACHE=ON
cd "$BUILD_DIR"

# Run Ninja with whatever parameters are passed to this script.
ninja "$@"
