#!/bin/bash

# Run a container to test that the generated packages can be successfully
# installed in a fresh Ubuntu system.

# Run from the top level of akceph-build with
# `test/debinstall/test_debinstall.sh -i` to get an interactive shell on the
# test container, instead of running /debinstall.sh as the entrypoint.

TOPDIR="$(realpath "$(dirname "$0")")"
BUILDDIR="$TOPDIR/ubuntu-container"
BUILD_RELEASEDIR="$BUILDDIR/release"

# shellcheck source=lib.sh
source "$TOPDIR/lib.sh"
# shellcheck source=vars.sh
source "$TOPDIR/vars.sh"

cd "$BUILDDIR"

interactive=0
squash=1
tag="latest"

function usage() {
    echo "Usage: $0 [-i] [-t tag] RELEASEDIR" >&2
    echo "  -i: run an interactive shell in the container" >&2
    echo "  -t tag: set the tag for the container image" >&2
    exit 1
}

while getopts "it:S" o; do
    case "${o}" in
        i)
            interactive=1
            ;;
        t)
            tag="${OPTARG}"
            echo "Setting tag '$tag'"
            ;;
        S)
            squash=0
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [[ $squash -eq 1 ]]; then
    # We can't reliably install things using pip, so just insist someone's
    # done the work if we're in squash mode.
    if ! command -v docker-squash >/dev/null; then
        echo "Squash mode is enabled, but docker-squash not found. Install it, or use -S." >&2
        exit 1
    fi
fi
if [[ $squash -eq 1 ]]; then
    runtag="$tag-squashed"
else
    runtag="$tag"
fi

releasedir="$1"
if [[ -z "$releasedir" ]]; then
    echo "RELEASEDIR must be set" >&2
    usage
fi
echo "Using releasedir='$releasedir'"
real_releasedir="$(realpath "$TOPDIR/$releasedir")"

if [[ ! -d "$real_releasedir" ]]; then
    echo "Dir $real_releasedir not present - is this the right directory?" >&2
    exit 1
fi
if [[ ! -d "$real_releasedir/Ubuntu/pool" ]]; then
    echo "Dir $real_releasedir/Ubuntu/pool not present - does it contain a completed build?" >&2
    exit 1
fi

# Copy the release to a known location relative to the Dockerfile. Don't copy
# WORKDIR; that's where it was built, and we don't need it in the image.
rsync -avP --delete --exclude WORKDIR "$real_releasedir"/ "$BUILD_RELEASEDIR"

set -e

set -x
$DOCKER build -t "$UBIMAGE":"$tag" -f "Dockerfile" .
set +x

if [[ $squash -eq 1 ]]; then
    docker-squash -f $(($(docker history "$UBIMAGE:$tag" | wc -l | xargs)-1)) -t "${UBIMAGE}:${tag}-squashed" "${UBIMAGE}:${tag}"
else
    $DOCKER image rm "${UBIMAGE}:${tag}-squashed" || true
fi

# shellcheck disable=SC2001
shortimage="$(echo "$UBIMAGE" | sed -e 's#^docker.io/##')"
echo "Displaying images matching $shortimage:$tag*"
docker images --filter=reference="$shortimage":"${tag}*"

if [[ $interactive -eq 1 ]]; then
    $DOCKER run -it  --entrypoint /bin/bash "${UBIMAGE}:${runtag}"
fi

echo "Standard image is ${UBIMAGE}:${tag}"
if [[ $squash -eq 1 ]]; then
    echo "Squashed image is ${UBIMAGE}:${tag}-squashed"
fi

exit 0
