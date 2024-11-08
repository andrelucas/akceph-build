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
    -C
        Do not clone the source code. This is useful for debugging the build.
        Implies -S and -R.
    -h
        Show this help message.
    -i
        Start an interactive shell in the container.
    -l
        Remove '--rm' from the Docker command line so we do not delete the
        container after the end of the run. This is useful for debugging, but
        can consume a lot of disk space. The exited container will be visible
        in 'docker ps -a' output. You can't easily run a stopped container, but
        you can copy files out of it and view its logs.
    -n
        Do not build the SRPMs (and by extension the RPMS). This is useful for
        debugging the build.
    -R
        Do not build the RPMS. This is useful for debugging the build.
    -s BRANCH
        The branch to check out. This is passed to the container build script.
    -S SRCDIR
        Use an external source directory mounted into the container. This is
        necessary for git repositories that require authentication to clone.

EOF
    exit 1
}

delete_container=1
PKG_DEBUG=0
EXTERNAL_SRC=0
interactive=0
NOCLONE=0
NORPMS=0
NOSRPMS=0
SRCDIR=""

while getopts "CdRhilns:S:" o; do
    case "${o}" in
        C)
            # NOCLONE implies NOSRPMS and NORPMS.
            # shellcheck disable=SC2034
            NOCLONE=1 NOSRPMS=1 NORPMS=1
            ;;
        d)
            echo "Enable debug build"
            # shellcheck disable=SC2034
            PKG_DEBUG=1
            ;;
        h)
            usage
            ;;
        i)
            interactive=1
            ;;
        l)
            delete_container=0
            ;;
        n)
            # NOSRPMS implies NORPMS, since there's nothing to build without
            # the source RPM.
            # shellcheck disable=SC2034
            NOSRPMS=1 NORPMS=1
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
            ;;
        S)
            EXTERNAL_SRC=1
            SRCDIR="$(realpath "${OPTARG}")"
            if [[ ! -f "$SRCDIR/make-srpm.sh" ]]; then
                echo "External source directory mounted to $SRCDIR does not appear to be a Ceph source clone" >&2
                exit 1
            fi
            echo "External source dir $SRCDIR"
            # For a SRCDIR build, clear down toplevel source artifacts. It
            # avoids confusion later - if we want to capture the source RPM
            # (we should) then there'll only be one *.src.rpm candidate.
            echo "Remove $SRCDIR/ceph.spec to guarantee RPM spec rebuild"
            rm -f "$SRCDIR"/ceph.spec
            echo "Remove any previous RPM-related build artifacts"
            rm -f "$SRCDIR"/ceph-*.rpm "$SRCDIR"/ceph-*.bz2

            ext_branch="$(cd "$SRCDIR" && git rev-parse --abbrev-ref HEAD)"
            if [[ $ext_branch == HEAD ]]; then
                echo "External source appears to be on a detached HEAD, detecting tag"
                ext_branch="$(cd "$SRCDIR" && git describe --abbrev=0 --tags)"
            fi
            echo "External source branch/tag $ext_branch"
            auto_reldir="rpmbuild_${ext_branch}"
            RPMBUILD_DIR="$(realpath "$(ref_to_folder "$auto_reldir")")"
            echo "Auto-set RPMBUILD_DIR='$RPMBUILD_DIR'"
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

if [[ -z "$BRANCH" && $EXTERNAL_SRC -ne 1 ]]; then
    echo "BRANCH must be set when a preexisting source dir (-S) is not specified" >&2
    exit 1
fi

# Make sure the ccache configuration is sane.
if [[ ! -d $CCACHE_DIR ]]; then
    mkdir -p "$CCACHE_DIR"
fi
if [[ ! -f $CCACHE_CONF ]]; then
    install tools/ccache.conf "$CCACHE_CONF"
fi

if [[ -z "$RPMBUILD_DIR" ]]; then
    echo "RPMBUILD_DIR is not set." >&2
    exit 1
fi

# Clear down the RPM build directory. This can fail as it's owned by root.
# Rather than use sudo, just fail with a clear error message.
if [[ -d "$RPMBUILD_DIR" ]]; then
    echo "Attempting to clear $RPMBUILD_DIR"
    if ! rm -rf "${RPMBUILD_DIR}" 2>/dev/null; then
        echo "Failed to clear down $RPMBUILD_DIR. You may need root privileges to delete it." >&2
        exit 1
    fi
fi
for d in BUILD RPMS SRPMS SOURCES SPECS; do
    mkdir -p "$RPMBUILD_DIR/$d"
done

# Copy build scripts into the context dir.
CONTEXTDIR="$BUILDDIR"
rm -rf "$CONTEXTDIR"/build
rsync -avP "$SCRIPTDIR"/build "$CONTEXTDIR"/

# Create an array of  -e arguments to `docker run`.
declare -a runenv
runenv=()
for ev in BRANCH CEPH_GIT PKG_DEBUG EXTERNAL_SRC NOCLONE NORPMS NOSRPMS SRCDIR; do
    runenv+=(-e)
    runenv+=("$ev=${!ev}")
done

# Get a tag that identifies the commit. We rely on docker to know when to
# rebuild things at a higher granularity, e.g. if pertinent build args change.
TAG="$(tag_for_local_head)"

if [[ $PKG_DEBUG -eq 1 ]]; then
    TAG="${TAG}-debug"
fi

# Build the image. This will check out the source code and update
# submodules, but won't do anything else. The rest is done in a container
# using this image.
set -x
docker build -t "$CENTOSIMAGE:$TAG" "$CONTEXTDIR"

declare -a runopt
runopt=()

runopt+=(-it)
if [[ $delete_container -eq 1 ]]; then
    runopt+=(--rm)
fi
if [[ $interactive -eq 1 ]]; then
    runopt+=(--entrypoint /bin/bash)
fi

if [[ $EXTERNAL_SRC -eq 1 ]]; then
    runopt+=(-v "$SRCDIR":/src)
fi

# Run the container, which will output to the release dir an rpmbuild/
# directory tree. We're interested in RPMS/ and SRPMS/ directories, and the
# rest can be discarded.
docker run \
    "${runenv[@]}" \
    "${runopt[@]}" \
    -v "$CCACHE_DIR":"$C_CCACHE" \
    -v "$RPMBUILD_DIR":"$C_RPMBUILD" \
    "$CENTOSIMAGE:$TAG" -- "$@"

# Clear down the BUILD/ part of the release tree, it's wasted space.
# This stuff might be owned by root, so allow it to fail. Pipe to dev null
# because the output makes a mess of the scrollback buffer.
rm -rf "$RPMBUILD_DIR"/BUILD 2>/dev/null || true
if [[ -d "$RPMBUILD_DIR"/BUILD ]]; then
	echo "BUILD dir exists in $RPMBUILD_DIR - you should delete it manually." >&2
fi
exit 0
