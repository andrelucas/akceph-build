#!/bin/bash

# Ceph build metascript. Runs *inside* the container.

## This is the architecture flag we set unless explicitly disabled.
FLAG_M_ARCH="-march=znver2"

SCRIPTDIR="$(realpath "$(dirname "$0")")"

function usage() {
    cat <<EOF
Usage: $0 [-b CMAKEBUILDTYPE] [-c CMAKEOPTION [...]] [-C] [-d|-D|-t] [-E] [-j NPROC] [-n] [-O DEB_BUILD_OPTIONS] [-R] [NINJA_TARGET...]

Where
    -A
        Do not set -march, let the compiler decide the architecture. This will
        result in slower generated code.
    -b CMAKEBUILDTYPE
        Set the CMake build type (default: RelWithDebInfo).
    -c CMAKEOPTION
        Pass a CMake option to the build, e.g. -DWITH_ASAN=ON, "-GUnix Makefiles".
    -C
        Disable use of ccache. This has a brutal build-time penalty.
    -d
        Build a Debian package using raw dpkg-buildpackage.
    -D
        Build Debian packages using SRC/make-deps.sh
    -E
        Use the (host) file tools/env to configure the environment for the build.
        Keep the file simple, and use it sparingly.
    -h
        Show this help message.
    -j NPROC
        Override the number of processors to use for the build. Default is half
        the value returned by nproc(1).
    -L
        Disable our override of the linker. Normally we'll explicitly set to use
        ld.gold(1).
    -n
        Do not build, just configure. Only useful for source and unit test builds,
        not for Debian package builds.
    -O DEB_BUILD_OPTIONS
        Pass options to the Debian build system.
    -R
        Normally we patch RocksDB to disable PORTABLE build mode. This option
        leaves it as-is.
    -t
        Run the unit tests.
    -x
        Build doxygen documentation. Builds into /src/build-doc, so will be visible
        outside the container.

    NINJA_TARGET
        The target to build with Ninja (if run without -d, -D or -t), e.g. radosgwd
        to build just RGW.

EOF
    exit 1
}

arch_set=1
BUILD_TYPE=RelWithDebInfo
deb_build_options=""
debbuild=0
doxygen=0
linker_override=1
nobuild=0
nproc_overridden=0
old_debbuild=0
rocksdb_portable=0
run_unittests=0
with_ccache=1

declare -a cmake_opts
cmake_opts=()

while getopts "Ab:c:CdDEhj:LnO:Rtx" o; do
    case "${o}" in
        A)
            arch_set=0
            ;;
        b)
            BUILD_TYPE=$OPTARG
            echo "Setting build type '$BUILD_TYPE'"
            ;;
        C)
            with_ccache=0
            # It's not enough to say WITH_CCACHE=OFF, do_cmake.sh detects the
            # binary. We're in a container, so just move it aside!
            if [[ -x /usr/local/bin/ccache ]]; then
                mv /usr/local/bin/ccache /usr/local/bin/ccache.disabled
            fi
            ;;
        c)
            # shellcheck disable=SC2206
            cmake_opts+=("$OPTARG")
            ;;
        d)
            debbuild=1
            ;;
        D)
            old_debbuild=1
            ;;
        E)
            if [[ ! -f $SCRIPTDIR/env ]]; then
                echo "No env file found in $SCRIPTDIR"
                exit 1
            fi
            use_envfile=1
            ;;
        h)
            usage
            ;;
        j)
            nproc_overridden=1
            BUILD_NPROC=$(OPTARG)
            ;;
        L)
            linker_override=0
            ;;
        n)
            nobuild=1
            ;;
        O)
            deb_build_options="$OPTARG"
            ;;
        R)
            rocksdb_portable=1
            ;;
        t)
            run_unittests=1
            ;;
        x)
            doxygen=1
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

if [[ $nproc_overridden -eq 0 ]]; then
    # The default is to use half the available processors.
    BUILD_NPROC=$(($(nproc) / 2))
fi
export BUILD_NPROC

# If the container build installed links for gcc-11, use them.
if [[ -f /usr/local/bin/gcc-11 ]]; then
    # These are required for Ceph 18.
    CCLINKPATH=/usr/local/bin  # These are the CMake symlinks.
    CC=$CCLINKPATH/gcc-11
    CXX=$CCLINKPATH/g++-11
    export CC CXX
fi

if [[ $arch_set -eq 1 ]]; then
    # Set the architecture to znver2. See
    # https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html but note that we're
    # running an old GCC.
    echo "Setting architecture flag $FLAG_M_ARCH"
    export CFLAGS="$FLAG_M_ARCH"
    export CXXFLAGS="$FLAG_M_ARCH"
fi

if [[ $rocksdb_portable -eq 0 ]]; then
    # Patch RocksDB to disable PORTABLE build mode.
    # Note this will get undone by the Debian build - it will need to be
    # patched in if we want it in the dpkgs.
    sed -i -e 's/\(rocksdb_CMAKE_ARGS -DPORTABLE=\)ON/\1OFF/' /src/cmake/modules/BuildRocksDB.cmake
fi

# Pull in the envfile if requested. This is completely unsafe; the envfile
# could easily wreak havoc.
if [[ $use_envfile -eq 1 ]]; then
    echo "BEGIN environment import"
    cat "$SCRIPTDIR/env"
    echo "END environment import"
    # shellcheck source=env.example
    source "$SCRIPTDIR/env"
fi

function old_debbuild() {
    # There are too many possibilities to attempt to automatically clean up
    # here. Just stop the build, and explain why.
    if [[ -e /release/Ubuntu ]]; then
        # The release directory might be different outside the container -
        # don't guess.
        echo "RELEASE_DIR/Ubuntu is present - will not overwrite" >&2
        exit 1
    fi
    # The Debian build switches to GNU Make, so we have to be careful how much
    # parallelism we ask for - Ninja deliberately limits it based on RAM. The
    # first parameter to make_debs.sh is the base directory for the built
    # images (it defaults to /tmp/release).
    env DEB_BUILD_OPTIONS="parallel=$BUILD_NPROC $deb_build_options" ./make-debs.sh /release "$@"
}

function debbuild() {
    env DEB_BUILD_OPTIONS="parallel=$BUILD_NPROC $deb_build_options" dpkg-buildpackage -uc -us "$@"
}

# Run CMake (via do_cmake.sh) and cd to the build directory.
function configure() {
    export BUILD_DIR=build.$BUILD_TYPE

    rm -rf "$BUILD_DIR"

    declare -a cmake_std_opts
    cmake_std_opts=()
    cmake_std_opts+=(-DALLOCATOR=tcmalloc)
    cmake_std_opts+=(-DBOOST_J="$BUILD_NPROC")
    cmake_std_opts+=(-DCMAKE_BUILD_TYPE="$BUILD_TYPE")
    cmake_std_opts+=(-DCMAKE_CXX_FLAGS_DEBUG=-fno-lto)
    cmake_std_opts+=(-DCMAKE_EXPORT_COMPILE_COMMANDS=ON)
    if [[ $with_ccache -eq 1 ]]; then
        cmake_std_opts+=(-DWITH_CCACHE=ON)
    fi
    if [[ $linker_override -eq 1 ]]; then
        # Explicitly use ld.gold(1)
        cmake_std_opts+=(-DCMAKE_LINKER=ld.gold)
        cmake_std_opts+=(-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=gold)
    fi

    echo "Configuring with: ${cmake_std_opts[*]} ${cmake_opts[*]}"
    echo "Note that do_cmake.sh might override some of these options."

    ./do_cmake.sh \
        "${cmake_std_opts[@]}" \
        "${cmake_opts[@]}"
    cd "$BUILD_DIR"
}

function srcbuild() {
    configure
    if [[ $nobuild -eq 1 ]]; then
        echo "Build skipped"
    else
        # Run Ninja with whatever parameters are passed to this script.
        ninja -j"$BUILD_NPROC" "$@"
    fi
}

function doxybuild() {
    configure
    ninja doxygen "$@"
}

function unittest() {
    cd /src
    ## XXX this is not reliable at the moment.
    # Hack the environment.
    env CC=gcc pip3 install xmlsec
    # It won't build unless the target is cleared.
    rm -rf build && ./run-make-check.sh
}

if [[ $doxygen -eq 1 ]]; then
    doxybuild "$@"
elif [[ $run_unittests -eq 1 ]]; then
    unittest "$@"
elif [[ $old_debbuild -eq 1 ]]; then
    old_debbuild "$@"
elif [[ $debbuild -eq 1 ]]; then
    debbuild "$@"
else
    srcbuild "$@"
fi

exit 0
