#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
source "$SCRIPTDIR/lib.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf $tmpdir' EXIT

function usage() {
    echo "Usage: $0 [-i]" 2>&2
    exit 1
}

interactive=0

declare -a runopt
runopt=()

while getopts "io:" o; do
    case "${o}" in
        i)
            interactive=1
            ;;
        o)
            # shellcheck disable=SC2206
            runopt+=($OPTARG)
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
./build-container.sh

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

set -e -x
$DOCKER run --rm \
    -v "/etc/passwd:/etc/passwd:ro" \
    -v "/etc/group:/etc/group:ro" \
    -v "$CEPH_SRC":"$C_SRC" \
    -v "$TOOLS_SRC":"$C_TOOLS" \
    -v "$CCACHE_DIR":"$C_CCACHE" \
    -e "CCACHE_DIR=$C_CCACHE" \
    "${runopt[@]}" "$IMAGENAME:$tag" "$@"
