#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"

function usage() {
    echo "Usage: $0 [-R]" 2>&2
    exit 1
}

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "$SCRIPTDIR")
trap 'test -n "$tmpdir" && rm -rf $tmpdir' EXIT

no_env=0
rebuild_container=0

while getopts "nR" o; do
    case "${o}" in
        n)
            no_env=1
            ;;
        R)
            rebuild_container=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

set -e

# shellcheck source=vars.sh.example
if [[ $no_env -eq 0 ]]; then
    source "$SCRIPTDIR/vars.sh"
fi
source "$SCRIPTDIR/lib.sh"

# Build the preinstall image in the temporary directory, so we can run
# concurrently with other builds.
PRE_DIR="$tmpdir/preinstall"
build_preinstall "$PRE_DIR" build-container
pushd "$(dirname "$PRE_DIR")"
tag=$(hash_dir "$(basename "$PRE_DIR")")
echo "Build: Preinstall image tag: $tag"
popd

if [[ $rebuild_container -eq 1 ]]; then
    echo "Cleaning preinstall image"
    $DOCKER image rm -f "$IMAGENAME:$tag" || true
fi

$DOCKER build -t "$IMAGENAME:$tag" .

