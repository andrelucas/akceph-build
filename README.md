# README for akceph-build

This is a simple Dockerised Ceph build.

## tl;dr

```sh

# Copy the configuration file and customise for your setup.
$ cp vars.sh.example vars.sh
$ vim vars.sh  # Make this match reality.

# Build from source into Linux binaries in BUILDDIR/bin.
$ ./build-ceph.sh

# Build Debian packages using `make-debs.sh` (v17).
$ ./build-ceph.sh -- -D

# Build Debian packages using `dpkg-buildpackage` (v18).
$ ./build-ceph.sh -- -d

# Just construct the build image. Note this will be customised to your
# source tree, as defined in vars.sh.
$ ./build-container.sh

# Get an interactive shell on the build image, with everything mounted
# ready to build.
$ ./build-ceph.sh -i

## Once inside the build image...

# Build fully.
root@eb10eda81490:/src# /tools/source-build.sh

# Build for debug (default is RelWithDebInfo).
root@eb10eda81490:/src# /tools/source-build.sh -t Debug
# Build with ASAN enabled.
root@eb10eda81490:/src# /tools/source-build.sh -c -DWITH_ASAN=ON
# Build with make(1) instead of Ninja. (Notice the quotes.)
root@eb10eda81490:/src# /tools/source-build.sh -c "-GUnix Makefiles"
# Build with the GOLD linker.
root@eb10eda81490:/src# /tools/source-build.sh \
  -c "-DCMAKE_LINKER=ld.gold" \
  -c "-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=gold"
# etc.

# You can pass options to the entrypoint in the container
# (source-build.sh by default) directly, by adding options to
# the entrypoint script after '--' on the build-ceph.sh command
# line:
$ ./build-ceph.sh -- -t Debug

# Or:

$ ./build-ceph.sh -- -DWITH_ASAN=ON

```

## Overview

This is designed to be a mltiuser build image that can be run by multiple
users simultaneously without problems, so long as the users are using separate
working copies. (It won't work if you do multiple builds from the same
checked-out source - sorry.)

### Build image

The build image consists of a bootstrap build environment for Ceph. It is
based on Ubuntu 20.04, and it installs basic tools before calling out to
`install-deps.sh` from the Ceph source to bring everything it needs in.

This is subtle. `install-deps.sh` varies from release to release, so we have
to be sensitive to this. My solution is to checksum everything from the source
that we need, and use that checksum as the tag to the Docker build image.
Then, when the builder goes to compile the source, it constructs the same
checksum and selects the appropriate Docker image.

This way, if we have two builds with different versions of Ceph, the build
scripts will automatically select the correct image, with `install-deps.sh`
pre-run. This is significant; the deps installer script is very slow, and for
an incremental build cycle it would be an intolerable nuisance.

The build image is configured to run a source build script by default.

### Build script.

The build script takes a few command line options, but essentially runs either
a source build (`./do-cmake.sh && ... && ninja`) or a Debian build
(`./make-debs.sh`).

By design the script is opinionated in how it builds. However, you can pass as
many `-c` options (to specify CMake options) to the build script as you like,
as shown in the examples above.

XXX more
