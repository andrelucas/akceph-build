# README for akceph-build

<!-- vscode-markdown-toc -->
* [tl;dr](#tldr)
* [Overview](#Overview)
	* [Build image](#Buildimage)
	* [Build script.](#Buildscript.)
* [Miscellanea](#Miscellanea)
	* [Why is it in a separate directory to the Ceph source?](#WhyisitinaseparatedirectorytotheCephsource)

<!-- vscode-markdown-toc-config
	numbering=false
	autoSave=true
	/vscode-markdown-toc-config -->
<!-- /vscode-markdown-toc -->

This is a simple Dockerised Ceph build on an Ubuntu 20.04 base. This makes the
generated binaries suitable for running on systems we have, natively or in a
container.

Note this doesn't work with Podman at the moment. It needs real Docker. With
Podman a lot more care is required with permissions for mounted directories,
and since Akamai is an Ubuntu house there's no clear incentive.

A separate repository based on upstream code will build final containers for
use external to the development team. This is a developer tool.

## <a name='tldr'></a>tl;dr

```sh

# Copy the configuration file and customise for your setup.
$ cp vars.sh.example vars.sh
$ vim vars.sh  # Make this match reality.

# Build from source into Linux binaries in BUILDDIR/bin. This is create for
# unit tests and vstart.sh clusters.
$ ./build-ceph.sh

# Get command help.
$ ./build-ceph.sh -- -h

... lots of Docker stuff ...

~/git/akceph-build
Usage: /tools/source-build.sh [-b CMAKEBUILDTYPE] [-c CMAKEOPTION [...]] [-C] [-d|-D|-t] [-E] [-j NPROC] [-n] [-O DEB_BUILD_OPTIONS] [NINJA_TARGET...]

Where
    -b CMAKEBUILDTYPE
        Set the CMake build type (default: RelWithDebInfo).
    -c CMAKEOPTION
        Pass a CMake option to the build, e.g. -DWITH_ASAN=ON, "-GUnix Makefiles".
    -C
        Disable use of ccache. This has a brutal build-time penalty.
    -d
        Build a Debian package using raw dpkg-buildpackage.
    -D
        Build Debian packages using SRC/make-deps.sh
    -E
        Use the file in the script directory to configure the environment
        for the build. Keep the file simple, and use it sparingly.
    -h
        Show this help message.
    -j NPROC
        Override the number of processors to use for the build. Default is half the
        value returned by nproc(1).
    -n
        Do not build, just configure. Only useful for source and unit test builds, not
        for Debian package builds.
    -O DEB_BUILD_OPTIONS
        Pass options to the Debian build system.
    -t
        Run the unit tests.
    NINJA_TARGET
        The target to build with Ninja (if run without -d, -D or -t), e.g. radosgwd to
        build just RGW.


# Build Debian packages using `make-debs.sh`. This will *torch*
# anything not in git inside your working copy - beware!
# Outputs go to release/ (relative to your akceph-build working copy) in
# the host.
$ ./build-ceph.sh -- -D

# Build Debian packages using `dpkg-buildpackage`. This too may wreak
# havoc in your working copy, be careful.
$ ./build-ceph.sh -- -d
#  '-d' is sometimes more helpful than -D because you can add extra
# options that will be passed to dpkg-buildpackage(1), which can drastically
# shorten build time. E.g.
$ ./build-ceph.sh -- -d --build=binary

# Both debian builds take the -o option to set DEB_BUILD_OPTIONS.
$ ./build-ceph.sh -- -d -O "nostrip"
# Of course these can be combined.
$ ./build-ceph.sh -- -d -O "nostrip" --build-binary

# Run the unit tests.
$ ./build-ceph.sh -- -t

# Just construct the build image. Note this will be customised to your
# source tree, as defined in vars.sh.
$ ./build-container.sh

## Interactive building.

# Get an interactive shell on the build image, with everything mounted
# ready to build.
$ ./build-ceph.sh -i

## Once inside the build image by using '-i'...

# Run normal commands.
root@eb10eda81490:/src# cd /src/build.Debug
root@eb10eda81490:/src# ninja
# Once you've build things, you can run vstart.sh on the outputs


# Build fully.
root@eb10eda81490:/src# /tools/source-build.sh

# Build for debug (default is RelWithDebInfo).
root@eb10eda81490:/src# /tools/source-build.sh -b Debug
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
$ ./build-ceph.sh -- -b Debug

# Or:

$ ./build-ceph.sh -- -DWITH_ASAN=ON

```

## <a name='Overview'></a>Overview

This is designed to be a mltiuser build image that can be run by multiple
users simultaneously without problems, so long as the users are using separate
working copies. (It won't work if you do multiple builds from the same
checked-out source - sorry.)

### <a name='Buildimage'></a>Build image

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

### <a name='Buildscript.'></a>Build script.

The build script takes a few command line options, but essentially runs either
a source build (`./do-cmake.sh && ... && ninja`) or a Debian build
(`./make-debs.sh` or `dpkg-buildpackage`).

By design the script is opinionated in how it builds. However, you can pass as
many `-c` options (to specify CMake options) to the build script as you like,
as shown in the examples above.

#### Power options

You can tweak how dpkg-buildpackage operates by using the `-O` option to
set `DEB_BUILD_OPTIONS`. If you don't know what this does, don't use it.

More powerfully still, you can pass in arbitrary environment variables via
file `tools/env`. These can make substantial differences to the output, and if
you try you can totally break things, so use this sparingly.

## <a name='Miscellanea'></a>Miscellanea

### What's this for?

This is to help Ceph developers. It builds consistently and automatically
(with good ccache support) into binaries and into Debian packages.

The aim is that the build machine or one's own machines can be used to build
consistent images. In particular, it needs to be possible to have multiple
builds of multiple versions of Ceph in flight at the same time.

A separate tool will be made for building 'final' container images for user
consumption.

### <a name='WhyisitinaseparatedirectorytotheCephsource'></a>Why is it in a separate directory to the Ceph source?

Largely because running a Debian build will obliterate anything that isn't
committed to git in the working copy. This is the voice of experience; you are
looking at the second version of this tool.


