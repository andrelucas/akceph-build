#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"

function usage() {
    echo "Usage: $0 [-nR]" 2>&2
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

# This section is fiddly. We need to create the environment to run
# install-deps.sh, which we'll call the 'preinstall'. It consists of
# install-deps.sh itself, and stuff in the debian/ directory. We'll only copy
# stuff in debian/ that's in git; this is because Debian build tools will
# often build into debian/, and it's always a shame to copy gigabytes of
# packages and build working directories when we don't mean to.
#
# There's an extra complication: `docker build` needs to know the directory
# in which we've built our preinstall environment. At build time, that's
# passed using a 'build arg'. However (there's always a 'however') if the
# build arg passed differs between builds, anything in the build that uses
# that build arg is invalidated. This means we'd re-run install-deps.sh every
# time, even for identical builds. The whole point of all this is to avoid
# these rebuilds, so we have to work around it.
#
# This is achieved here by building the preinstall environment twice. The
# first time is in a tmp directory, and is just to get the hash of the
# preinstall environment. Then, we rebuild it again, this time in a directory
# that has the hash baked into the path. Then, an identical build will use the
# same path, so will use an identical build arg, so the cache will be valid
# and the prebuilt container can be used instead of re-running
# install-deps.sh.

# Build the preinstall image in the temporary directory, so we can run
# concurrently with other builds.
PRE_DIR="$tmpdir/preinstall"
build_preinstall "$PRE_DIR" build-container1
pushd "$tmpdir"
phash=$(hash_dir "preinstall")
echo "Build: Preinstall hash: $phash"
popd

# Recreate the preinstall image in a directory that will match an identical
# later build. This is important - it's how we reuse the image. If we change
# the directory the image is in, Docker will re-run install-deps.sh.
FIXED_PRE_DIR="$SCRIPTDIR/preinstall.$phash/preinstall"
rm -rf "$FIXED_PRE_DIR"
build_preinstall "$FIXED_PRE_DIR" build-container2
pushd "preinstall.$phash"
checkhash=$(hash_dir "preinstall")
if [[ "$phash" != "$checkhash" ]]; then
    echo "Hash mismatch: $phash != $checkhash" >&2
    exit 1
fi
popd

tag="$(imagetag_for_preinstall_hash "$phash")"
echo "Build: Image tag: $tag"

if [[ $rebuild_container -eq 1 ]]; then
    echo "Cleaning preinstall image"
    $DOCKER image rm -f "$IMAGENAME:$tag" || true
fi

FIXED_PRE_DIR_RELATIVE="${FIXED_PRE_DIR#"$SCRIPTDIR/"}" # Strip PWD from the FIXED_PRE_DIR.

$DOCKER build --build-arg "PRE_SOURCE_DIR=$FIXED_PRE_DIR_RELATIVE" -t "$IMAGENAME:$tag" .

