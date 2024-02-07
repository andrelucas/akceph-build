#!/bin/bash

SCRIPTDIR="$(dirname "$0")"
source "$SCRIPTDIR/vars.sh" || exit 1

set -e

# Run this inside a flock(1) so concurent builds out of the same working copy
# don't stomp on each other. If this is irksome, have multiple working copies.
(
    flock -n 9 || (echo "Another build is in progress" && exit 1)
    build_preinstall "$PWD"/preinstall
    pushd "$(dirname "$PRE_DIR")"
    tag=$(hash_dir "$(basename "$PRE_DIR")")
    echo "Build: Preinstall image tag: $tag"
    popd

    $DOCKER build -t "$IMAGENAME:$tag" .

) 9>"$SCRIPTDIR"/preinstall.lock

