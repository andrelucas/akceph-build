#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"

function usage() {
    cat <<EOF
Usage: $0 [-b CMAKEBUILDTYPE] [-c CMAKEOPTION [...]] [-C] [-d|-D|-t] [-E] [-j NPROC] [-n] [-O DEB_BUILD_OPTIONS] [NINJA_TARGET...]

Where
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
        Use the file in the script directory to configure the environment
        for the build. Keep the file simple, and use it sparingly.
    -h
        Show this help message.
    -j NPROC
        Override the number of processors to use for the build. Default is half the
        value returned by nproc(1).
    -n
        Do not build, just configure. Only useful for source and unit test builds, not
        for Debian package builds.
    -O DEB_BUILD_OPTIONS
        Pass options to the Debian build system.
    -t
        Run the unit tests.
    NINJA_TARGET
        The target to build with Ninja (if run without -d, -D or -t), e.g. radosgwd to
        build just RGW.

EOF
    exit 1
}

BUILD_TYPE=RelWithDebInfo
deb_build_options=""
debbuild=0
nobuild=0
old_debbuild=0
run_unittests=0
nproc_overridden=0
with_ccache=1

declare -a cmake_opts
cmake_opts=()

while getopts "b:c:CdDEhj:nO:t" o; do
    case "${o}" in
        b)
            BUILD_TYPE=$OPTARG
            echo "Setting build type '$BUILD_TYPE'"
            ;;
        C)
            with_ccache=0
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
        n)
            nobuild=1
            ;;
        O)
            deb_build_options="$OPTARG"
            ;;
        t)
            run_unittests=1
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

# Pull in the envfile if requested. This is completely unsafe; the envfile
# could easily wreak havoc.
if [[ $use_envfile -eq 1 ]]; then
    echo "BEGIN environment import"
    cat "$SCRIPTDIR/env"
    echo "END environment import"
    source "$SCRIPTDIR/env"
fi

function old_debbuild() {
    sudo apt-get install -y reprepro
    # The debian build switches to GNU Make, so we have to be careful how much
    # parallelism we ask for.
    # The first parameter is the base directory for the built images (it
    # defaults to /tmp/release).
    env DEB_BUILD_OPTIONS="parallel=$BUILD_NPROC $deb_build_options" ./make-debs.sh /release "$@"
}

function debbuild() {
    sudo apt-get install -y debhelper
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
    cmake_std_opts+=(-DCMAKE_EXPORT_COMPILE_COMMANDS=ON)
    if [[ $with_ccache -eq 1 ]]; then
        cmake_std_opts+=(-DWITH_CCACHE=ON)
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
        ninja "$@"
    fi
}

function unittest() {
    configure
    if [[ $nobuild -eq 1 ]]; then
        echo "Build skipped"
    else
        ninja tests && ctest -j "$BUILD_NPROC" --output-on-failure "$@"
    fi
}

if [[ $run_unittests -eq 1 ]]; then
    unittest "$@"
elif [[ $old_debbuild -eq 1 ]]; then
    old_debbuild "$@"
elif [[ $debbuild -eq 1 ]]; then
    debbuild "$@"
else
    srcbuild "$@"
fi
