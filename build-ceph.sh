#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"
SCRIPTNAME="$(basename "$0")"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
source "$SCRIPTDIR/lib.sh"

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "$SCRIPTDIR")
trap 'rm -rf $tmpdir >/dev/null 2>&1 || true' EXIT

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
    -p
        Attempt to push the Docker image to the registry. You may need to log into
        the registry to do this, and this script will not help you with that.
    -r RELEASE_DIR
        Override the release directory. This is where the build artifacts will be
        placed. Helpful if multiple builds are in progress.
    -R
        Pass options to _build-container.sh
    -S CEPH_SRC
        Override the source directory. This is where the Ceph source tree is
        located.

Anything after '--' is passed to the build script run in the container, which by
default is tools/source-build.sh.

EOF
    exit 1
}

interactive=0
push_image=0
releasedir_set=0
skip_clean=0
source_branch="NOTSET"
source_checkout=0

declare -a bcopt runopt
bcopt=()
runopt=()

while getopts "Cio:pr:Rs:S:" o; do
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
            echo "Using source branch '$source_branch'"
            if [[ $releasedir_set -ne 1 ]]; then
                # Auto-set the release directory to match the source branch,
                # after transforming the source branch to a valid directory name.
                auto_reldir="release_$OPTARG"
                RELEASE_DIR="$(realpath "$(ref_to_folder "$auto_reldir")")"
                echo "Auto-set RELEASE_DIR='$RELEASE_DIR'"
            fi
            ;;
        p)
            push_image=1
            ;;
        r)
            # Use realpath(1) to resolve to a full pathname. `docker run`
            # doesn't like relative paths.
            RELEASE_DIR="$(realpath "$OPTARG")"
            mkdir -p "$RELEASE_DIR" || (echo "Failed to create '$RELEASE_DIR'" >&2; exit 1)
            echo "Override RELEASE_DIR='$RELEASE_DIR'"
            releasedir_set=1
            ;;
        R)
            bcopt+=(-R)
            ;;
        S)
            CEPH_SRC="$(realpath "$OPTARG")"
            if [[ ! -f $CEPH_SRC/install-deps.sh ]]; then
                echo "Source directory '$CEPH_SRC' does not contain install-deps.sh" >&2
                exit 1
            fi
            echo "Override CEPH_SRC='$CEPH_SRC'"
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
    # fetch, that breaks it. We can't do a --depth=1 shallow clone of the
    # toplevel because this breaks `make-dist` in the Ceph repo, which uses
    # `git describe` and needs some history.
    git clone \
        -c advice.detachedHead=false \
        -b "$source_branch" "$CEPH_GIT" "$tmpdir"/src
fi

# Create a preinstall environment that matches the one built into the base
# image. This allows multiple versions of the base image to match the
# install-deps.sh and debian/ directories in the Ceph source tree.
build_preinstall "$tmpdir/preinstall" build-ceph1
pushd "$tmpdir"
phash="$(hash_dir preinstall)"
echo "Run: Preinstall hash: $phash"
tag="$(imagetag_for_preinstall_hash "$phash")"
echo "Run: Image tag: $tag"
popd

# Rely on Docker and this script to not rebuild from scratch. Note the '-n',
# so the environment doesn't get reloaded.
$DOCKER pull "$IMAGENAME:$tag" || ./_build-container.sh -n "${bcopt[@]}"
if [[ $push_image -eq 1 ]]; then
    echo "Attempting to push $IMAGENAME:$tag to remote registry"
    $DOCKER push "$IMAGENAME:$tag" || echo "Failed to push image, continuing" >&2
fi

# Make sure the ccache configuration is sane.
if [[ ! -d $CCACHE_DIR ]]; then
    mkdir -p "$CCACHE_DIR"
fi
if [[ ! -f $CCACHE_CONF ]]; then
    install tools/ccache.conf "$CCACHE_CONF"
fi

set -e
$DOCKER run \
    -v "/etc/passwd:/etc/passwd:ro" \
    -v "/etc/group:/etc/group:ro" \
    -v "$CCACHE_DIR":"$C_CCACHE" \
    -v "$CEPH_SRC":"$C_SRC" \
    -v "$RELEASE_DIR":"$C_RELEASE" \
    -e "CCACHE_DIR=$C_CCACHE" \
    "${runopt[@]}" "$IMAGENAME:$tag" "$@"

echo "$SCRIPTNAME: Done"
exit 0
