#!/bin/bash

# Build an 'official' container image using a modified version of the upstream
# build tool.

SCRIPTDIR="$(realpath "$(dirname "$0")")"
SCRIPTNAME="$(basename "$0")"
BUILDDIR="$SCRIPTDIR/official-build"
CCDIR="$SCRIPTDIR/third_party/ceph-container"

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
    -r RPMBUILD_SRC
        The path to the RPM build source directory.
    -W 
        Persist the web server container after the script exits. This will
        leave the temporary directory and container in place!
EOF
    exit 1
}

RPMBUILD_SRC=""
createrepo_only=0
webserver_persist=0
webserver_port="$(shuf -i 1024-49151 -n 1)"

while getopts "Chp:r:W" o; do
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

# Copy the built RPMS and SRPMS to our temporary directory.
repodir="$(realpath "$tmpdir"/yumrepo)"
mkdir "$repodir"
pushd "$repodir"

echo "Copying source RPMS and SRPMS to $(pwd)"
rsync -a "$RPMBUILD_SRC"/RPMS "$RPMBUILD_SRC"/SRPMS .

for d in RPMS/x86_64 RPMS/noarch SRPMS; do
    pushd $d
    echo "Creating Yum repo in $(pwd)"
    createrepo_c .
    popd
done

id="$(docker run -d -p "$webserver_port":80 -v "$repodir":/usr/share/nginx/html:ro --name "$tmpcontainer" nginx:alpine)"
docker ps -f "id=$id"

# Check we can actually reach the webserver we just started.
webserver_url="http://$(hostname -f):$webserver_port"
echo "Testing web server on $webserver_url"
if ! curl "$webserver_url/RPMS/noarch/repodata/repomd.xml" >/dev/null; then
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
make FLAVORS=reef,centos,8 \
    BASEOS_REGISTRY=quay.io/centos BASEOS_REPO=centos BASEOS_TAG=stream8 \
    CUSTOM_CEPH_YUM_REPO="$webserver_url" \
    build

exit 0
