# shellcheck shell=bash

# Take a checksum of a given directory.
function hash_dir() {
    local d="$1"
    if [[ -z "$d" ]]; then
        echo "Usage: hash_dir DIR" >&2
        return 1
    fi
    find "$d" -type f -print0 | \
        xargs -0 sha256sum | \
        sort | \
        sha256sum | \
        cut -c1-16
}

function build_preinstall() {
    local PRE_DIR="$1" ROLE="$2"
    if [[ -z "$PRE_DIR" || -z "$ROLE" ]]; then
        echo "Usage: build_preinstall PRE_DIR ROLE" >&2
        return 1
    fi
    rm -rf "$PRE_DIR"
    mkdir -p "$PRE_DIR"
    echo "$ROLE: Construct preinstall environment in '$PRE_DIR' from '$CEPH_SRC'"
    cp "$CEPH_SRC"/install-deps.sh "$PRE_DIR"
    # Copy *only the git-tracked files* from the debian directory.
    pushd "$CEPH_SRC/debian" || exit 1
    mkdir -p "$PRE_DIR/debian"
    git ls-tree -r HEAD --name-only | xargs -I {} cp --parents {} "$PRE_DIR/debian"
    popd || exit 1
}

# Silence pushd/popd output. Most of the time it's just noise.
pushd () {
    command pushd "$@" > /dev/null || exit
}
popd () {
    command popd > /dev/null || exit
}
