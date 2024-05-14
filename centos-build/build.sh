#!/bin/bash

if [[ -z $BRANCH && $EXTERNAL_SRC -ne 1 ]]; then
    echo "BRANCH is not set." >&2
    exit 1
fi
if [[ -z $CEPH_GIT ]]; then
    echo "CEPH_GIT is not set." >&2
    exit 1
fi

if [[ $EXTERNAL_SRC -eq 0 ]]; then
    # Clone the source directly. This will only work if there's a URI that
    # doesn't require authentication.
    cat <<EOF
    **
    ** Using repo $CEPH_GIT branch $BRANCH
    **
    ** NOSRPMS=$NOSRPMS NORPMS=$NORPMS
    **
EOF

    set -e -x

    cd /
    git clone "$CEPH_GIT" -c advice.detachedHead=false -b "$BRANCH" /src

else
    # Use an external source directory mounted into the container.
    if [[ ! -f /src/make-srpm.sh ]]; then
        echo "External source directory mounted to /src does not appear to be a Ceph source clone" >&2
        exit 1
    fi
    echo "Using external source tree mounted into /src"
    # Without this, git will essentially refuse to operate on the source tree.
    git config --global --add safe.directory "*"
fi

cd /src
git submodule update --init --recursive


if [[ $NOSRPMS -eq 1 ]]; then
    echo "NOSRPMS=1, stopping before building source RPM."
    exit 0
fi
./make-srpm.sh
rpm -i /src/ceph-*.src.rpm

# Set RPM build options.
cat <<EOF >$HOME/.rpmmacros
# Make it clear where this package is from.
%packager Akamai Ceph Engineering

# Override the 'fascist build policy'. Without this, any unpackaged files
# (e.g. the in-tree Expat library and tools) will cause the build to fail.
%_unpackaged_files_terminate_build 0
EOF

cd ~/rpmbuild
dnf builddep -y SPECS/ceph.spec
if [[ $NORPMS -eq 1 ]]; then
    echo "NORPMS=1, stopping before building target RPMs."
    exit 0
fi

rpmbuild -ba SPECS/ceph.spec
exit 0
