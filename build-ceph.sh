#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
source "$SCRIPTDIR/lib.sh"

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "$SCRIPTDIR")
trap 'rm -rf $tmpdir >/dev/null 2>&1' EXIT

function usage() {
    cat >&2 <<EOF
Usage: $0 [-CiR] [-o RUNOPT] [--] [OPTIONS-TO-BUILD-SCRIPT]
Where:
    -C
        Do not clean the container after the end of the run. This is useful for
        debugging, but can consume a lot of disk space.
    -i
        Start an interactive shell in the container.
    -o
        Pass additional options to 'docker run'.
    -r RELEASE_DIR
        Override the release directory. This is where the build artifacts will be
        placed. Helpful if multiple builds are in progress.
    -R
        Pass options to _build-container.sh

Anything after '--' is passed to the build script run in the container, which by
default is tools/source-build.sh.

EOF
    exit 1
}

interactive=0
skip_clean=0
source_branch="NOTSET"
source_checkout=0

declare -a bcopt runopt
bcopt=()
runopt=()

while getopts "Cio:s:r:R" o; do
    case "${o}" in
        C)
            skip_clean=1
            ;;
        i)
            interactive=1
            ;;
        o)
            # shellcheck disable=SC2206
            runopt+=($OPTARG)
            ;;
        s)
            source_checkout=1
            source_branch="$OPTARG"
            ;;
        r)
            # Use realpath(1) to resolve to a full pathname. `docker run`
            # doesn't like relative paths.
            RELEASE_DIR="$(realpath "$OPTARG")"
            mkdir -p "$RELEASE_DIR" || (echo "Failed to create '$RELEASE_DIR'" >&2; exit 1)
            echo "Override RELEASE_DIR='$RELEASE_DIR'"
            ;;
        R)
            bcopt+=(-R)
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [[ $interactive -eq 1 ]]; then
    runopt+=(--entrypoint /bin/bash)
fi

runopt+=(-it) # Always interactive - we want to be able to Ctrl-C.

if [[ $skip_clean -ne 1 ]]; then
    runopt+=(--rm)
fi

# Set up the source checkout directory if required. This needs to occur before
# the _build-container.sh script is run, because it uses the source tree to
# construct the preinstall environment.
if [[ $source_checkout -eq 0 ]]; then
    echo "Will use a pre-existing source tree in '$CEPH_SRC'"
else
    if [[ -z $CEPH_GIT ]]; then
        echo "Source checkout requested, but CEPH_GIT is not set"
        exit 1
    fi
    if [[ -z $source_branch ]]; then
        echo "Source branch cannot be empty"
        exit 1
    fi
    CEPH_SRC="$tmpdir/src"
    echo "Cloning '$CEPH_GIT' branch '$source_branch' to '$CEPH_SRC'"
    # Let the build sdo the submodule update. We can't do a shallow submodule
    # fetch, that breaks it.
    git clone --depth 1 \
        -c advice.detachedHead=false \
        -b "$source_branch" "$CEPH_GIT" "$tmpdir"/src
fi

# Rely on Docker and this script to not rebuild from scratch. Note the '-n',
# so the environment doesn't get reloaded.
./_build-container.sh -n "${bcopt[@]}"

# Make sure the ccache configuration is sane.
if [[ ! -d $CCACHE_DIR ]]; then
    mkdir -p "$CCACHE_DIR"
fi
if [[ ! -f $CCACHE_CONF ]]; then
    install tools/ccache.conf "$CCACHE_CONF"
fi

# Create a preinstall environment that matches the one built into the base
# image. This allows multiple versions of the base image.
build_preinstall "$tmpdir/preinstall" build-ceph
pushd "$tmpdir"
tag=$(hash_dir preinstall)
echo "Run: Preinstall image tag: $tag"
popd

set -e
$DOCKER run \
    -v "/etc/passwd:/etc/passwd:ro" \
    -v "/etc/group:/etc/group:ro" \
    -v "$CCACHE_DIR":"$C_CCACHE" \
    -v "$CEPH_SRC":"$C_SRC" \
    -v "$RELEASE_DIR":"$C_RELEASE" \
    -v "$TOOLS_SRC":"$C_TOOLS" \
    -e "CCACHE_DIR=$C_CCACHE" \
    "${runopt[@]}" "$IMAGENAME:$tag" "$@"

# WORKDIR is disposable, and can be large.
rm -rf "$RELEASE_DIR"/Ubuntu/WORKDIR

exit 0
