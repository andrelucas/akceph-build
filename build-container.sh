#!/bin/bash

SCRIPTDIR="$(dirname "$0")"
source "$SCRIPTDIR/vars.sh" || exit 1

PRE_DIR=$PWD/preinstall
rm -rf "$PRE_DIR"
mkdir -p preinstall
cp "$CEPH_SRC"/install-deps.sh "$PRE_DIR"
cp -r "$CEPH_SRC"/debian "$PRE_DIR"/

$DOCKER build -t "$IMAGE" .
