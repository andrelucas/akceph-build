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
    local pre_dir="$1"
    local role="$2"
    if [[ -z "$pre_dir" || -z "$role" ]]; then
        echo "Usage: build_preinstall pre_dir role" >&2
        return 1
    fi
    rm -rf "$pre_dir"
    mkdir -p "$pre_dir"
    echo "$role: Construct preinstall environment in '$pre_dir' from '$CEPH_SRC'"
    cp "$CEPH_SRC"/install-deps.sh "$pre_dir"
    # Copy *only the git-tracked files* from the debian directory.
    pushd "$CEPH_SRC/debian" || exit 1
    mkdir -p "$pre_dir/debian"
    git ls-tree -r HEAD --name-only | xargs -I {} cp --parents {} "$pre_dir/debian"
    popd || exit 1
}

function imagetag_for_preinstall_hash() {
    local phash="$1"
    local gitref
    if [[ -z "$phash" ]]; then
        echo "Usage: imagetag_for_preinstall_hash PREINSTALL_HASH" >&2
        return 1
    fi
    gitref="$(git rev-parse --short HEAD)"
    if [[ -z "$gitref" ]]; then
        echo "Failed to get git ref" >&2
        return 1
    fi
    echo "${gitref}-${phash}"
}

# Silence pushd/popd output. Most of the time it's just noise.
pushd () {
    command pushd "$@" > /dev/null || exit
}
popd () {
    command popd > /dev/null || exit
}
