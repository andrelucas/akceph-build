#!/bin/bash

# Run a container to test that the generated packages can be successfully
# installed in a fresh Ubuntu system.

# Run from the top level of akceph-build with
# `test/debinstall/test_debinstall.sh -i` to get an interactive shell on the
# test container, instead of running /debinstall.sh as the entrypoint.

SCRIPTDIR="$(dirname "$0")"
TOPDIR="$(realpath "$SCRIPTDIR/../..")"

# shellcheck source=../../lib.sh
source "$TOPDIR/lib.sh"
# shellcheck source=../../vars.sh
source "$TOPDIR/vars.sh"

declare -a runopt
runopt=()

if [[ -z "$RELEASEDIR" ]]; then
    echo "RELEASEDIR must be set" >&2
    exit 1
fi

interactive=0
releasedir="${RELEASEDIR}"

while getopts "i" o; do
    case "${o}" in
        i)
            interactive=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

echo "Using releasedir='$releasedir'"
real_releasedir="$(realpath "$releasedir")"

if [[ ! -d "$real_releasedir" ]]; then
    echo "Dir $real_releasedir not present - is this the right directory?" >&2
    exit 1
fi
if [[ ! -d "$real_releasedir/Ubuntu/pool" ]]; then
    echo "Dir $real_releasedir/Ubuntu/pool not present - does it contain a completed build?" >&2
    exit 1
fi

if [[ $interactive -eq 1 ]]; then
    echo "Enabling interactive mode"
    runopt+=(--entrypoint /bin/bash)
fi

set -e

set -x
$DOCKER build -t debinstall:"$releasedir" -f "$SCRIPTDIR/Dockerfile" .
$DOCKER run --rm -v "$real_releasedir":/release -it \
    "${runopt[@]}" \
    debinstall:"$releasedir"
# Attempt to clean up. It's ok for this to fail, though it might waste some
# space.
$DOCKER image rm debinstall:"$releasedir" || true
exit 0
