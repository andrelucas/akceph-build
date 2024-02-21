# shellcheck shell=bash

# Take a checksum of a given directory.
function hash_dir() {
    local d="$1"
    echo "Hashing $d" >&2  # Don't write to stdout!
    find "$d" -type f -print0 | \
        xargs -0 sha256sum | \
        sort | \
        sha256sum | \
        cut -c1-16
}

function build_preinstall() {
    local PRE_DIR="$1"
    rm -rf "$PRE_DIR"
    mkdir -p "$PRE_DIR"
    echo "Construct preinstall environment from $CEPH_SRC"
    cp "$CEPH_SRC"/install-deps.sh "$PRE_DIR"
    # Copy *only the git-tracked files* from the debian directory.
    pushd "$CEPH_SRC/debian" || exit 1
    mkdir -p "$PRE_DIR/debian"
    git ls-tree -r HEAD --name-only | xargs -I {} cp --parents {} "$PRE_DIR/debian"
    popd || exit 1
}
