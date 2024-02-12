#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
source "$SCRIPTDIR/lib.sh"

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "$SCRIPTDIR")
trap 'rm -rf $tmpdir' EXIT

function usage() {
    cat >&2 <<EOF
Usage: $0 [-irR] [-o RUNOPT] [--] [OPTIONS-TO-BUILD-SCRIPT]
Where:
    -i
        Start an interactive shell in the container.
    -o
        Pass additional options to 'docker run'.
    -r
        Remove the container after the run. Saves space, but might delete work.
    -R
        Pass options to build-container.sh

Anything after '--' is passed to the build script run in the container, which by
default is tools/source-build.sh.

EOF
    exit 1
}

interactive=0

declare -a bcopt runopt
bcopt=()
runopt=()

while getopts "io:rR" o; do
    case "${o}" in
        i)
            interactive=1
            ;;
        o)
            # shellcheck disable=SC2206
            runopt+=($OPTARG)
            ;;
        r)
            runopt+=(--rm)
            ;;
        R)
            bcopt+=(-R)
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [[ $interactive -eq 1 ]]; then
    runopt+=(--entrypoint /bin/bash)
fi

runopt+=(-it) # Always interactive - we want to be able to Ctrl-C.

# Rely on Docker and this script to not rebuild from scratch.
./build-container.sh "${bcopt[@]}"

# Make sure the ccache configuration is sane.
if [[ ! -d $CCACHE_DIR ]]; then
    mkdir -p "$CCACHE_DIR"
fi
if [[ ! -f $CCACHE_CONF ]]; then
    install tools/ccache.conf "$CCACHE_CONF"
fi

# Create a preinstall environment that matches the one built into the base
# image. This allows multiple versions of the base image.
build_preinstall "$tmpdir/preinstall"
pushd "$tmpdir"
tag=$(hash_dir preinstall)
echo "Run: Preinstall image tag: $tag"
popd

set -e
$DOCKER run \
    -v "/etc/passwd:/etc/passwd:ro" \
    -v "/etc/group:/etc/group:ro" \
    -v "$CCACHE_DIR":"$C_CCACHE" \
    -v "$CEPH_SRC":"$C_SRC" \
    -v "$RELEASE_DIR":"$C_RELEASE" \
    -v "$TOOLS_SRC":"$C_TOOLS" \
    -e "CCACHE_DIR=$C_CCACHE" \
    "${runopt[@]}" "$IMAGENAME:$tag" "$@"
