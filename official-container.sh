#!/bin/bash

# Build an 'official' container image using a modified version of the upstream
# build tool.

SCRIPTDIR="$(realpath "$(dirname "$0")")"
SCRIPTNAME="$(basename "$0")"
OFFICIAL_BUILD_DIR="$SCRIPTDIR/official-build"
CCDIR="$SCRIPTDIR/third_party/ceph-container"

RHUTIL_IMAGE_NAME=rhutil
GEN2_IMAGE_NAME=akdaemon-gen2

CENTOS_STREAM_VERSION=8
CENTOS_STREAM_TAG="stream$CENTOS_STREAM_VERSION"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
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
    -h
        Show this help message.
    -p PORT
        The port to use for the web server. Default is a random port between
        1024 and 49151.
    -r RPMBUILD_SRC
        The path to the RPM build source directory.
    -s BRANCH
        Build RPMs for the specified branch before building the container.
        This sets the RPMBUILD_SRC path to rpmbuild_BRANCH, and you won't need
        to use -r.
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
RPMBUILD_SRC=""
createrepo_only=0
upload=0
webserver_persist=0
webserver_port="$(shuf -i 1024-49151 -n 1)"

while getopts "Chp:r:s:uW" o; do
    case "${o}" in
        C)
            createrepo_only=1
            ;;
        p)
            webserver_port="${OPTARG}"
            if [[ ! "$webserver_port" =~ ^[0-9]{1,5}$ ]]; then
                echo "Invalid port number: $webserver_port"
                exit 1
            fi
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

# -s => build RPMs first.
if [[ $build -eq 1 ]]; then
    echo "** Building RPMs for branch $build_branch **"
    ./rpm-build.sh -s "$build_branch"
fi

# Build a container with the RPM-related tools we need. This allows us to
# build the final image on non-Red Hat systems.
pushd $SCRIPTDIR/official-build
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
# The final tag used by ceph-container is computed.
cc_image_tag="${release_tag}-${ceph_majorversion_name}-centos-${CENTOS_STREAM_TAG}-$(arch)"

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
webserver_url="http://$(hostname -f):$webserver_port"
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

# Use ceph-container to build the image, using the web server we just started.
git submodule update --init
pushd "$CCDIR"
# Clear down staging/ to avoid any confusion. Don't run 'clean.all', it
# deletes images which might cause problems.
rm -rf staging/*
# Run a very, very specific build target.
make FLAVORS="$ceph_majorversion_name",centos,"$CENTOS_STREAM_VERSION" \
    RELEASE="$release_tag" \
    TAG_REGISTRY="$CEPH_CONTAINER_REGISTRY" \
    BASEOS_REGISTRY=quay.io/centos BASEOS_REPO=centos BASEOS_TAG="$CENTOS_STREAM_TAG" \
    CUSTOM_CEPH_YUM_REPO="$webserver_url" \
    build

docker image ls -f 'reference=$release_tag'

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
docker build -t "$CEPH_CONTAINER_REGISTRY/$GEN2_IMAGE_NAME:$cc_image_tag" .

# Optionally push all the generated images.
for img in daemon-base daemon demo "$GEN2_IMAGE_NAME"; do
    fqimg="$CEPH_CONTAINER_REGISTRY/$img:$cc_image_tag"
    if [[ $upload -eq 1 ]]; then
        docker push "$CEPH_CONTAINER_REGISTRY/$img:$cc_image_tag"
    else
        echo "Skipped push of $fqimg"
    fi
done

exit 0
