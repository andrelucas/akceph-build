#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"
SCRIPTNAME="$(basename "$0")"
BUILDDIR="$SCRIPTDIR/centos-build"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
source "$SCRIPTDIR/lib.sh"

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "$SCRIPTDIR")
trap 'rm -rf $tmpdir >/dev/null 2>&1 || true' EXIT

function usage() {
    cat >&2 <<EOF
Usage: $SCRIPTNAME [-h] [-- [OPTIONS-TO-BUILD-SCRIPT]]
Where:
    -h
        Show this help message.
    -i
        Start an interactive shell in the container.
    -R
        Do not build the RPMS. This is useful for debugging the build.
    -s BRANCH
        The branch to check out. This is passed to the container build script.
    -S
        Do not build the SRPMs (and by extension the RPMS). This is useful for
        debugging the build.
EOF
    exit 1
}

NOCLONE=0
NORPMS=0
NOSRPMS=0
interactive=0

set -x

while getopts "CRhis:S" o; do
    case "${o}" in
        C)
            # NOCLONE implies NOSRPMS and NORPMS.
            # shellcheck disable=SC2034
            NOCLONE=1 NOSRPMS=1 NORPMS=1
            ;;
        h)
            usage
            ;;
        i)
            interactive=1
            ;;
        R)
            # shellcheck disable=SC2034
            NORPMS=1
            ;;
        s)
            BRANCH="${OPTARG}"
            echo "source branch $BRANCH"
            # Auto-set the release directory to match the source branch,
            # after transforming the source branch to a valid directory name.
            auto_reldir="rpmbuild_${BRANCH}"
            RPMBUILD_DIR="$(realpath "$(ref_to_folder "$auto_reldir")")"
            echo "Auto-set RPMBUILD_DIR='$RPMBUILD_DIR'"
            mkdir -p "$RPMBUILD_DIR"
            ;;
        S)
            # NOSRPMS implies NORPMS, since there's nothing to build without
            # the source RPM.
            # shellcheck disable=SC2034
            NOSRPMS=1 NORPMS=1           
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [[ -z "$CENTOSIMAGE" ]]; then
    echo "CENTOSIMAGE is not set." >&2
    exit 1
fi

if [[ -z "$BRANCH" ]]; then
    echo "BRANCH is not set." >&2
    exit 1
fi

# Make sure the ccache configuration is sane.
if [[ ! -d $CCACHE_DIR ]]; then
    mkdir -p "$CCACHE_DIR"
fi
if [[ ! -f $CCACHE_CONF ]]; then
    install tools/ccache.conf "$CCACHE_CONF"
fi

# Copy build scripts into the context dir.
CONTEXTDIR="$BUILDDIR"
rm -rf "$CONTEXTDIR"/build
rsync -avP "$SCRIPTDIR"/build "$CONTEXTDIR"/

# Create an array of  -e arguments to `docker run`.
declare -a runenv
runenv=()
for ev in BRANCH CEPH_GIT NOCLONE NORPMS NOSRPMS; do
    runenv+=(-e)
    runenv+=("$ev=${!ev}")
done

# Get a tag that identifies the commit. We rely on docker to know when to
# rebuild things at a higher granularity, e.g. if pertinent build args change.
TAG="$(tag_for_local_head)"

# Build the image. This will check out the source code and update
# submodules, but won't do anything else. The rest is done in a container
# using this image.
set -x
docker build -t "$CENTOSIMAGE:$TAG" "$CONTEXTDIR"

declare -a runopt
runopt=()

runopt+=(-it)
if [[ $interactive -eq 1 ]]; then
    runopt+=(--entrypoint /bin/bash)
fi

# Run the container, which will output to the release dir an rpmbuild/
# directory tree. We're interested in RPMS/ and SRPMS/ directories, and the
# rest can be discarded.
docker run \
    "${runopt[@]}" \
    "${runenv[@]}" \
    -v "$CCACHE_DIR":"$C_CCACHE" \
    -v "$RPMBUILD_DIR":"$C_RPMBUILD" \
    --rm \
    "$CENTOSIMAGE:$TAG" -- "$@"

# Clear down the BUILD/ part of the release tree, it's wasted space.
# This stuff might be owned by root, so allow it to fail.
rm -rf "$RPMBUILD_DIR"/BUILD/* 2>&1 | true
exit 0
