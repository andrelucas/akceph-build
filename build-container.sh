#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"


function usage() {
    echo "Usage: $0 [-R]" 2>&2
    exit 1
}

no_env=0
rebuild_container=0

while getopts "nR" o; do
    case "${o}" in
        n)
            no_env=1
            ;;
        R)
            rebuild_container=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

set -e

# shellcheck source=vars.sh.example
if [[ $no_env -eq 0 ]]; then
    source "$SCRIPTDIR/vars.sh"
fi
source "$SCRIPTDIR/lib.sh"

# Run this inside a flock(1) so concurent builds out of the same working copy
# don't stomp on each other. If this is irksome, have multiple working copies.
(
    flock -n 9 || (echo "Another build is in progress" && exit 1)
    PRE_DIR="$SCRIPTDIR/preinstall"
    build_preinstall "$PRE_DIR"
    pushd "$(dirname "$PRE_DIR")"
    tag=$(hash_dir "$(basename "$PRE_DIR")")
    echo "Build: Preinstall image tag: $tag"
    popd

    if [[ $rebuild_container -eq 1 ]]; then
        echo "Cleaning preinstall image"
        $DOCKER image rm -f "$IMAGENAME:$tag" || true
    fi

    $DOCKER build -t "$IMAGENAME:$tag" .

) 9>"$SCRIPTDIR"/preinstall.lock

