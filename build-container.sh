#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
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

    $DOCKER build -t "$IMAGENAME:$tag" .

) 9>"$SCRIPTDIR"/preinstall.lock

