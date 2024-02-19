#!/bin/bash

# Fetch and build OpenSSL 3 from source.

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "/tmp")
trap 'rm -rf $tmpdir' EXIT

set -e
source config.env

if [[ $AKCEPH_ENABLE_OPENSSL3 != 1 ]]; then
    echo "AKCEPH_ENABLE_OPENSSL3 is not 1, skipping OpenSSL 3.x build"
    exit 0
fi

SSL_DIR=/usr/local/openssl3

set -x
cd "$tmpdir"
git clone git://git.openssl.org/openssl.git
cd openssl
git checkout -b openssl-3.2.1 tags/openssl-3.2.1
env CC="gcc" "CFLAGS=-march=$AKCEPH_GCC_TARGET_ARCH" \
    ./Configure --prefix="$SSL_DIR" --openssldir="$SSL_DIR" --libdir="$SSL_DIR/lib"
make -j"$(( $(nproc)/2 ))"
# install_sw doesn't build manpages.
make install_sw