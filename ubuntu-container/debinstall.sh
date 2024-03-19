#!/bin/bash

# - set up a local apt repository containing the release files
# - install Ceph and any other components we care about
# - run smoke tests

set -e

function get_release_var() {
    local varname="$1"
    local val
    val="$(grep "^$varname=" /etc/os-release | cut -d'=' -f2)"
    if [[ -z $val ]]; then
        echo "Could not find $varname in /etc/os-release" >&2
        exit 1
    fi
    echo "$val"
}

function pushd () {
    command pushd "$@" >/dev/null
}
function popd () {
    command popd >/dev/null
}

version_codename="$(get_release_var VERSION_CODENAME)"

pushd /release/Ubuntu/pool/main/c/ceph
ceph_version="$(find . -name "ceph_*_amd64.deb" -type f | sort | head -1 | sed -e 's#^\./ceph_##' -e 's/_amd64.deb$//')"
popd
echo "Ceph package version: $ceph_version"

cat <<EOF >/etc/apt/sources.list.d/ceph.list
deb [arch=amd64 trusted=yes] file:/release/Ubuntu/ $version_codename main
EOF

set -x
export DEBIAN_FRONTEND=noninteractive
apt-get -q update
apt-get -qy install "ceph=${ceph_version}" "radosgw=${ceph_version}"

# Don't leave the Debian package sources in place.
rm -rf /release
rm /etc/apt/sources.list.d/ceph.list
apt-get -q update
apt-get clean

exit 0
