#!/bin/bash

# Run some basic tests on the installed packages. For example, make sure
# various binaries at least run.

set -e

for bin in ceph ceph-osd ceph-mon radosgw; do
    if ! which $bin; then
        echo "Could not find $bin in PATH"
        exit 1
    fi
    if ! $bin --version; then
        echo "Could not run $bin --version"
        exit 1
    fi
done
