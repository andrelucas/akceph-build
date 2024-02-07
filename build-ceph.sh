#!/bin/bash

SCRIPTDIR="$(dirname "$0")"
source "$SCRIPTDIR/vars.sh" || exit 1

function usage() {
    echo "Usage: $0 [-s <45|90>] [-p <string>]" 2>&2
    exit 1
}

interactive=0

declare -a runcmd runopt
runopt=()
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

set -e -x
$DOCKER run --rm \
    -v "/etc/passwd:/etc/passwd:ro" \
    -v "/etc/group:/etc/group:ro" \
    -v "$CEPH_SRC":"$C_SRC" \
    -v "$TOOLS_SRC":"$C_TOOLS" \
    -v "$CCACHE_DIR":"$C_CCACHE" \
    -v "$CCACHE_CONF":"$C_CCACHE/ccache.conf" \
    "${runopt[@]}" $IMAGE "${runcmd[@]}"
