#!/bin/bash

# Run some basic tests on the installed packages. For example, make sure
# various binaries at least run.

set -e

for bin in ceph ceph-osd ceph-mon radosgw; do
    if ! which $bin; then
        echo "ERROR: Could not find $bin in PATH"
        exit 1
    fi
    if ! $bin --version; then
        echo "ERROR: Could not run $bin --version"
        exit 1
    fi
done

# Check that radosgw is properly linked against libtcmalloc.
if ! ldd /usr/bin/radosgw | grep -q libtcmalloc; then
    echo "ERROR: radosgw is not linked against libtcmalloc"
    echo "BEGIN ldd output"
    ldd /usr/bin/radosgw
    echo "END ldd output"
    exit 1
fi
