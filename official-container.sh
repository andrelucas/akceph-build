#!/bin/bash

# Build an 'official' container image using a modified version of the upstream
# build tool.

SCRIPTDIR="$(realpath "$(dirname "$0")")"
SCRIPTNAME="$(basename "$0")"
OFFICIAL_BUILD_DIR="$SCRIPTDIR/official-build"
CCDIR="$SCRIPTDIR/third_party/ceph-container"

RHUTIL_IMAGE_NAME=rhutil
GEN2_IMAGE_NAME=akdaemon-gen2
GEN2_DEBUG_IMAGE_NAME=akdaemon-gen2-debug

# CENTOS_STREAM_VERSION=9
# CENTOS_STREAM_TAG="stream$CENTOS_STREAM_VERSION"
ROCKY_VERSION=8
ROCKY_TAG="$ROCKY_VERSION"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
# shellcheck source=lib.sh
source "$SCRIPTDIR/lib.sh"

tmpdir=$(mktemp -d "tmp.XXXXXXXXXX" -p "$SCRIPTDIR")
tmpcontainer=$(mktemp -u "web.XXXXXXXXXX")
# shellcheck disable=SC2317
function exit_trap() {
    set +x
    if [[ -n "$tmpcontainer" && "$webserver_persist" -ne 1 ]]; then
        echo "Cleaning up"
        docker stop "$tmpcontainer" || true
        rm -rf "$tmpdir" >/dev/null 2>&1
    else
        echo "Skip cleanup"
    fi
}
trap exit_trap EXIT

function usage() {
    cat <<EOF >&2
Usage: $SCRIPTNAME [-h] | -r RPMBUILD_SRC
Where:
    -C
        Only run createrepo and start the web server, don't build the image.
    -d
        Add a '-debug' suffix to the image tag. Otherwise there's no easy way
        to tell the difference between a debug and non-debug image.
    -h
        Show this help message.
    -p PORT
        The port to use for the web server. Default is a random port between
        1024 and 49151.
    -P PORT
        Advanced: Skip the build of the ceph-container images (base, daemon and
        demo). This is for debugging the package builder, to help devs skip the
        time-consuming ceph-container build step if and only if those containers
        are already built on the local machine. However, you have to specify
        the Yum web server port that was used when those containers were built.
        I did say it was an advanced option.
    -r RPMBUILD_SRC
        The path to the RPM build source directory.
    -s BRANCH
        Build RPMs for the specified branch before building the container.
        This sets the RPMBUILD_SRC path to rpmbuild_BRANCH, and you won't need
        to use -r.
    -S BUILD_SRC
        Build RPMs for the specified source directory before building the
        container. This sets the RPMBUILD_SRC path to rpmbuild_SRC, and you
        won't need to use -r. Use this form if your git repo needs
        authentication to clone it.
    -u
        Upload (push) generated images to the upstream container registry.
    -W 
        Persist the web server container after the script exits. This will
        leave the temporary directory and container in place!
EOF
    exit 1
}

build=0
build_branch=""
build_src=""
createrepo_only=0
PKG_DEBUG=0
RPMBUILD_SRC=""
skip_cc_build=0
upload=0
webserver_persist=0
webserver_port="$(shuf -i 1024-49151 -n 1)"

while getopts "Cdhp:P:r:s:S:uW" o; do
    case "${o}" in
        C)
            createrepo_only=1
            ;;
        d)
            echo "Will mark as DEBUG build"
            PKG_DEBUG=1
            ;;
        p)
            webserver_port="${OPTARG}"
            if [[ ! "$webserver_port" =~ ^[0-9]{1,5}$ ]]; then
                echo "Invalid port number: $webserver_port"
                exit 1
            fi
            ;;
        P)
            # Skip the ceph-container builds. Assumes they already exist, it
            # will fail if they don't.
            skip_cc_build=1
            webserver_port="${OPTARG}"
            echo "Skipping ceph-container builds, using webserver port $webserver_port"
            ;;
        r)
            RPMBUILD_SRC="$(realpath "${OPTARG}")"
            echo "RPMBUILD_SRC: $RPMBUILD_SRC"
            ;;
        s)
            build=1
            build_branch="${OPTARG}"
            RPMBUILD_SRC="$(realpath "rpmbuild_${build_branch}")"
            ;;
        S)
            build=1
            build_src="$(realpath "${OPTARG}")"
            echo "Using external source directory: $build_src"
            SRCDIR="$build_src"
            ext_branch="$(cd "$SRCDIR" && git rev-parse --abbrev-ref HEAD)"
            if [[ $ext_branch == HEAD ]]; then
                echo "External source appears to be on a detached HEAD, detecting tag"
                ext_branch="$(cd "$SRCDIR" && git describe --abbrev=0 --tags)"
            fi
            echo "External source branch/tag $ext_branch"
            RPMBUILD_SRC="$(realpath "rpmbuild_${ext_branch}")"
            echo "Will build to $RPMBUILD_SRC"
            ;;
        u)
            upload=1
            ;;
        W)
            webserver_persist=1
            ;;
        h|*)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "$RPMBUILD_SRC" ]; then
    echo "RPMBUILD_SRC (-r option) is required"
    exit 1
fi

declare -a build_opts
build_opts=()
if [[ $PKG_DEBUG -eq 1 ]]; then
    build_opts+=("-d")
fi

# -s => build RPMs first.
if [[ $build -eq 1 ]]; then
    if [[ -n $build_src ]]; then
        echo "Building RPMs for external source directory $build_src"
        ./rpm-build.sh -S "$build_src" "${build_opts[@]}"
    else
        echo "** Building RPMs for branch $build_branch **"
        ./rpm-build.sh -s "$build_branch" "${build_opts[@]}"
    fi
fi

# Build a container with the RPM-related tools we need. This allows us to
# build the final image on non-Red Hat systems.
pushd "$SCRIPTDIR"/official-build
docker build -t "$RHUTIL_IMAGE_NAME:latest" -f Dockerfile.rhutil .
popd

# Run a command in the rhutil container, mounting the directory named in the
# first parameter into the same directory in the container. The container runs
# as the current uid:gid, so the permissions shouldn't get wedged.
#
# This is so we can build Red Hat containers on non-Red Hat hosts. Here we
# only need rpm and createrepo_c, but it's a relatively general-purpose
# utility.
#
function rhutil_run_mount() {
    local mdir="$1"
    shift
    if [[ ! -d $mdir ]]; then
        echo "${FUNCNAME[0]}: Directory '$mdir' does not exist" >&2
        exit 1
    fi
    echo "Run in rhutil ($RHUTIL_IMAGE_NAME:latest) with mounted '$mdir': $*" >&2
    # Run in the container. Mount $mdir into the container with the same
    # directory name, and set the working directory to that directory.
    # The --security-opt is to prevent a weird error, detailed here:
    #   https://gist.github.com/nathabonfim59/b088db8752673e1e7acace8806390242
    docker run \
        --user "$(id -u)":"$(id -g)" \
        --rm \
        -v "$mdir":"$mdir" -w "$mdir" \
        --security-opt seccomp=unconfined \
        "$RHUTIL_IMAGE_NAME:latest" \
        sh -c "$*"
}

# Extract some version information (and invalidate bad directories in the
# process).
rpm_testfile=$(ls "$RPMBUILD_SRC"/RPMS/noarch/cephadm*.rpm)
if [[ -z $rpm_testfile || ! -e "$rpm_testfile" ]]; then
    echo "cephadm RPM not found in $RPMBUILD_SRC/RPMS/noarch" >&2
    exit 1
fi
# rpm_version will be the Ceph version, e.g. 18.2.1.
rpm_version=$(rhutil_run_mount "$RPMBUILD_SRC" rpm -qp --queryformat '%{VERSION}' "$rpm_testfile")
# This is the Ceph major version, e.g. 17 or 18.
ceph_majorversion=$(echo "$rpm_version" | cut -d. -f1)

# We need the text name for the Ceph release.
ceph_majorversion_name=""
case "$ceph_majorversion" in
    17)
        ceph_majorversion_name="quincy"
        ;;
    18)
        ceph_majorversion_name="reef"
        ;;
    *)
        echo "Unknown or unsupported Ceph major version '$ceph_majorversion'" >&2
        exit 1
        ;;
esac

# rpm_pkgrelease will be the 'sub-version', e.g. 35.g649cb767ced.el8 . This is
# the automatically-generated release number from Ceph's build process (it
# uses `git describe`). The RPM file has a platform suffix (e.g. '.el8').
rpm_pkgrelease="$(rhutil_run_mount "$RPMBUILD_SRC" rpm -qp --queryformat '%{RELEASE}' "$rpm_testfile")"
# rpm_release is rpm_pkgrelease minus the platform suffix. In the example for
# rpm_pkgrelease, this will be simply 35.g649cb767ced .
# shellcheck disable=SC2001
rpm_release="$(echo "$rpm_pkgrelease" | sed -E -e 's/.el[0-9]+$//')"
# This is what we'll tag our container.
release_tag="${rpm_version}-${rpm_release}"
# If we're told to mark as debug, add a suffix to the Docker image tag.
if [[ $PKG_DEBUG -eq 1 ]]; then
    release_tag="${release_tag}_debug"
fi
# The final tag used by ceph-container is computed.
cc_image_tag="${release_tag}-${ceph_majorversion_name}-rocky-${ROCKY_TAG}-$(arch)"

cat <<EOF
Package metadata:
  rpm_version=$rpm_version
  rpm_pkgrelease=$rpm_pkgrelease
  rpm_release=$rpm_release
  release_tag=$release_tag
  ceph_majorversion=$ceph_majorversion
  ceph_majorversion_name=$ceph_majorversion_name
  cc_image_tag=$cc_image_tag
EOF


# Copy the built RPMS and SRPMS to our temporary directory.
repodir="$(realpath "$tmpdir"/yumrepo)"
mkdir "$repodir"
pushd "$repodir"

echo "Copying source RPMS and SRPMS to $(pwd)"
rsync -a "$RPMBUILD_SRC"/RPMS "$RPMBUILD_SRC"/SRPMS .
chown -R "$(id -u):$(id -g)" .

# Run createrepo_c on relevant directories.
for d in RPMS/x86_64 RPMS/noarch SRPMS; do
    echo "Creating Yum repo in $d"
    rhutil_run_mount "$repodir" createrepo_c $d
done

# Start a web server on the repos we just created.
id="$(docker run -d -p "$webserver_port":80 -v "$repodir":/usr/share/nginx/html:ro --name "$tmpcontainer" nginx:alpine)"
docker ps -f "id=$id"

# Check we can actually reach the webserver we just started.
#
# Kludge: We need to do extra work because we can't rely on the host's FQDN
# being resolvable from DNS, which in turn means it probably won't be
# resolvable from inside a container. Do the name resolution on the host.
#
# This would best be resolved by having the hosts in the DNS, or by having
# access to more sophisticated orchestration e.g. k8s or even Docker Compose.
#
webserver_name="$(hostname -f)"
# This is painful. Try really heard to get an IPv4 address.
webserver_ip="$(getent ahosts "$webserver_name" | grep STREAM | grep -v ':' | head -1 | awk '{print $1}')"
if [[ -z $webserver_ip ]]; then
    echo "Failed to get an IPv4 address for $webserver_name" >&2
    exit 1
fi
webserver_url="http://$webserver_ip:$webserver_port"
echo "Web server FQDN '$webserver_name' IP '$webserver_ip' URL '$webserver_url'"

echo "Testing web server on $webserver_url"
retries=3
retry=1
success=0
while [ $retry -le $retries ]; do
    echo "Attempt $retry of $retries"
    if curl -s "$webserver_url/RPMS/noarch/repodata/repomd.xml" >/dev/null; then
        success=1
        break
    fi
    retry=$((retry + 1))
    sleep 1
done
if [[ $success -ne 1 ]]; then
    echo "Failed to reach the web server we just started on $webserver_url" >&2
    exit 1
fi

if [ $createrepo_only -eq 1 ]; then
    exit 0
fi

popd

if [[ $skip_cc_build -eq 1 ]]; then
    echo "Skipping ceph-container builds (they MUST be prebuild or later steps will fail)"
else
    # Use ceph-container to build the image, using the web server we just started.
    git submodule update --init --remote
    pushd "$CCDIR"
    # Clear down staging/ to avoid any confusion. Don't run 'clean.all', it
    # deletes images which might cause problems.
    rm -rf staging/*
    # Run a very, very specific build target.
    make FLAVORS="$ceph_majorversion_name",rocky,"$ROCKY_VERSION" \
        RELEASE="$release_tag" \
        TAG_REGISTRY="$CEPH_CONTAINER_REGISTRY" \
        BASEOS_REGISTRY=docker.io/library BASEOS_REPO=rockylinux BASEOS_TAG="$ROCKY_TAG" \
        CUSTOM_CEPH_YUM_REPO="$webserver_url" \
        build

    docker image ls -f 'reference=$release_tag'
fi

# Now we have three images, daemon-base, daemon, and demo. We want to take the
# daemon image as the base for an image that gen2 will use.

gen2_image_dir="$tmpdir/gen2-image"
mkdir -p "$gen2_image_dir"
pushd "$gen2_image_dir"
daemon_image="$CEPH_CONTAINER_REGISTRY/daemon:$cc_image_tag"

# Generate a Dockerfile for the gen2 image.
sed \
    -e "s#__BASE_IMAGE__#$daemon_image#g" \
    "$OFFICIAL_BUILD_DIR"/Dockerfile.in >Dockerfile
# Build the gen2 image.
docker build -t "$CEPH_CONTAINER_REGISTRY/$GEN2_IMAGE_NAME:$cc_image_tag" .

# Generate a Dockerfile for the debug gen2 image. This is the gen2 image plus
# all the debug symbols.
sed \
    -e "s#__BASE_IMAGE__#$daemon_image#g" \
    "$OFFICIAL_BUILD_DIR"/Dockerfile.debug.in >Dockerfile.debug
# Build the debug image.
docker build -f Dockerfile.debug -t "$CEPH_CONTAINER_REGISTRY/$GEN2_DEBUG_IMAGE_NAME:$cc_image_tag" .

# Optionally push all the generated images.
for img in daemon-base daemon demo "$GEN2_IMAGE_NAME" "$GEN2_DEBUG_IMAGE_NAME"; do
    fqimg="$CEPH_CONTAINER_REGISTRY/$img:$cc_image_tag"
    if [[ $upload -eq 1 ]]; then
        docker push "$fqimg"
    else
        echo "Skipped push of $fqimg"
    fi
done

exit 0
