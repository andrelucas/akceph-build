#!/bin/bash

function usage() {
    echo "Usage: $0 [-i]" 2>&2
    exit 1
}

debbuild=0
releasetype=RelWithDebInfo

declare -a cmake_opts
cmake_opts=()

while getopts "c:dt:" o; do
    case "${o}" in
        c)
            # shellcheck disable=SC2206
            cmake_opts+=("$OPTARG")
            ;;
        d)
            debbuild=1
            ;;
        t)
            BUILD_TYPE=$OPTARG
            echo "Setting build type '$BUILD_TYPE'"
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

set -e
cd /src

# Without this git(1) will object to the directory being owned by a different
# user. The wildcard means it applies to submodules as well.
git config --global --add safe.directory "*"

export NINJA_STATUS="[%p :: t=%t/f=%f/r=%r :: %e] "

BUILD_NPROC="${BUILD_NPROC:-$(nproc)}"
export BUILD_NPROC

function srcbuild() {
    export BUILD_DIR=build.$BUILD_TYPE

    rm -rf "$BUILD_DIR"

    set -x
    ./do_cmake.sh -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_BUILD_TYPE="$releasetype" \
        -DALLOCATOR=tcmalloc \
        -DBOOST_J="$BUILD_NPROC" \
        -DWITH_CCACHE=ON \
        "${cmake_opts[@]}"
    cd "$BUILD_DIR"

    # Run Ninja with whatever parameters are passed to this script.
    ninja
}

function debbuild() {
    ./make-debs.sh
}

if [[ $debbuild -eq 1 ]]; then
    debbuild
else
    srcbuild
fi
