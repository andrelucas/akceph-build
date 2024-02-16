#!/bin/bash

# Install golang and useful tools for building Ceph.

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "/tmp")
trap 'rm -rf $tmpdir' EXIT

set -e
source config.env

if [[ $AKCEPH_ENABLE_GO != 1 ]]; then
    echo "AKCEPH_ENABLE_GO is not 1, skipping golang build"
    exit 0
fi

echo "Fetching golang ${AKCEPH_GOLANG_VERSION}"
TARBALL="go${AKCEPH_GOLANG_VERSION}.linux-amd64.tar.gz"
URL="https://go.dev/dl/${TARBALL}"
DL="${tmpdir}/go.tar.gz"
curl -L -o "$DL" "${URL}"
sum="$(sha256sum "$DL" | cut -d' ' -f1)"
if [[ $sum != "$AKCEPH_GOLANG_CHECKSUM" ]]; then
    echo "Checksum mismatch for golang tarball"
    exit 1
fi

# The tarball unpacks to prefix 'go/', so we can just un-tar it.
rm -rf /usr/local/go
echo "Unpacking to /usr/local/go"
tar -C /usr/local -xzf "$DL"

# Quick check.
gobin=/usr/local/go/bin/go
$gobin version

# Install tools.
$gobin install github.com/bufbuild/buf/cmd/buf@v1.29.0
