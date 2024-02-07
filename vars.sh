# shellcheck shell=bash

export CCACHE_DIR=$HOME/.ccache
# Make CCACHE_CONF under CCACHE_DIR or you'll confuse matters.
export CCACHE_CONF=$CCACHE_DIR/ccache.conf
export CEPH_SRC=~/git/ceph
export DOCKER=docker
export IMAGENAME=cbuild
export TOOLS_SRC="$PWD/tools"

export C_CCACHE=/ccache
export C_SRC=/src
export C_TOOLS=/tools

# Take a checksum of a given directory.
function hash_dir() {
    local d="$1"
    find "$d" -type f -print0 | \
        xargs -0 sha256sum | \
        sha256sum | \
        cut -c1-16
}

function build_preinstall() {
    PRE_DIR="$1"
    rm -rf "$PRE_DIR"
    mkdir -p "$PRE_DIR"
    cp "$CEPH_SRC"/install-deps.sh "$PRE_DIR"
    cp -r "$CEPH_SRC"/debian "$PRE_DIR"
}
