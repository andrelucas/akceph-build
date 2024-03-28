#!/bin/bash

if [[ -z $BRANCH ]]; then
    echo "BRANCH is not set." >&2
    exit 1
fi
if [[ -z $CEPH_GIT ]]; then
    echo "CEPH_GIT is not set." >&2
    exit 1
fi

cat <<EOF
**
** Using repo $CEPH_GIT branch $BRANCH
**
** NOSRPMS=$NOSRPMS NORPMS=$NORPMS
**
EOF

set -e -x

cd /
git clone "$CEPH_GIT" -c advice.detachedHead=false -b "$BRANCH" /src && \
cd /src
git submodule update --init --recursive

if [[ $NOSRPMS -eq 1 ]]; then
    echo "NOSRPMS=1, stopping before building source RPM."
    exit 0
fi
./make-srpm.sh
rpm -i /src/ceph-*.src.rpm

cd ~/rpmbuild
dnf builddep -y SPECS/ceph.spec
if [[ $NORPMS -eq 1 ]]; then
    echo "NORPMS=1, stopping before building target RPMs."
    exit 0
fi

rpmbuild -ba SPECS/ceph.spec
exit 0
