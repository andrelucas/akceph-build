# README for akceph-build

<!-- vscode-markdown-toc -->
* [tl;dr](#tldr)
* [Recommended use](#Recommendeduse)
* [Overview](#Overview)
	* [Build image](#Buildimage)
		* [Container builds for the uninitiated](#Containerbuildsfortheuninitiated)
		* [Binary dependency compilation and install](#Binarydependencycompilationandinstall)
		* [`install-deps.sh` and multiple versions](#install-deps.shandmultipleversions)
		* [`install-deps.sh` speed hack](#install-deps.shspeedhack)
	* [`build-ceph.sh` - the build script.](#build-ceph.sh-thebuildscript.)
		* [Power options](#Poweroptions)
	* [`build-container.sh` - the container builder](#build-container.sh-thecontainerbuilder)
	* [`source-build.sh` - the Ceph builder script inside the container](#source-build.sh-theCephbuilderscriptinsidethecontainer)
* [Miscellanea](#Miscellanea)
	* [What's this for?](#Whatsthisfor)
	* [Why is it in a separate directory to the Ceph source?](#WhyisitinaseparatedirectorytotheCephsource)

<!-- vscode-markdown-toc-config
	numbering=false
	autoSave=true
	/vscode-markdown-toc-config -->
<!-- /vscode-markdown-toc -->

This is a simple Dockerised Ceph build on an Ubuntu 20.04 base. This makes the
generated binaries suitable for running on systems we have, natively or in a
container. It also builds standard Debian packages.

This is a container with a standard (Ceph version-dependent) build image that
you can use as a playground. It will build standard debs, sure, but it's also
a pretty useful development tool. You can trash your own working copy, sure,
because that's mounted into the container. However you're not hurting the host
system at all, and if you break it, just restart the container. It won't hurt
a bit.

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

# Build from existing source dir into Linux binaries in
# build.RelWithDebInfo/bin.
$ ./build-ceph.sh

# Same, but clone the source directly. Provide a reference to clone.
# (If you provide a tag, you'll get a 'detached HEAD' warning from git.
# That's ok.)
$ ./build-ceph.sh -s v18.2.1

# All-in-one: Clone, build debs. This is great for CI jobs. The
# double-hyphens matter.
$ ./build-ceph.sh -s v18.2.1 -- -D

# Get an interactive shell on the build container (existing source).
$ ./build-ceph.sh -i

# Same, but with a clean clone.
$ ./build-ceph.sh -i -s v17.2.7

# Run a Debug build in build.Debug/bin. I recommend a preexisting source
# tree if you're debugging, otherwise it's going to be very tiresom to
# make changes.
$ ./build-ceph.sh -- -b Debug

# Get command help. Note the double-hyphens - you're passing options to a
# script that runs inside the container.
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

# Build the doxygen docs.
$ ./build-ceph.sh -- -x
# To view the doxygen HTTP site, defaults to localhost:8000.
$ cd SRCDIR/build-doc/doxygen/html && python -m http.server

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

## <a name='Recommendeduse'></a>Recommended use

For **development**, I recommend running in interactive mode (`./build-ceph.sh
-i`). You can run whatever CMake you like that way.

If you want the standard `do_cmake.sh` invocation, you can do `./build-ceph.sh
-- -n -b Debug` which will stop before running ninja, and configure
in Debug mode. Then you can run in interactive mode with `-i` and change to
the build directory and build whatever you like - `ninja radosgwd` (`ninja
radosgw` for Ceph 18) is a personal favourite.

For **vstart.sh** runs, you can do the development build as above. You can run
`vstart.sh` as you normally would, with the only constraint that the ports it
opens won't by default be visible outside the container. If you know you're
going to do this, you can add port forwards to `docker run` and fix the ports
used by `vstart.sh` - this is a quite powerful way to run a dev cluster.

You can also run `vstart.sh` or anything else it builds in the host, though -
you'll have to do `export LD_LIBARY_PATH=<SRCDIR>/build.Debug/lib` (and
probably have run `install-deps.sh` in the host) before this will work.

For **standard builds**, do `./build-ceph -D`. This will, after some setup,
run `make_debs.sh` and build Debian packages. Note that this will *trash*
anything non-standard in your working copy! Commit (and ideally push) anything
in your local working copy before doing this, or you'll lose it. I mean it.

## <a name='Overview'></a>Overview

This is designed to be a mltiuser build image that can be run by multiple
users simultaneously without problems, so long as the users are using separate
working copies. (It won't work if you do multiple builds from the same
checked-out source - sorry.)

### <a name='Buildimage'></a>Build image

The build image consists of a bootstrap build environment for Ceph. It is
based on Ubuntu 20.04, and it installs basic tools and custom binary
dependencies before calling out to `install-deps.sh` from the Ceph source to
bring everything it needs in.

#### <a name='Containerbuildsfortheuninitiated'></a>Container builds for the uninitiated

A few notes for anyone not used to building in Docker containers.

It's important to know the difference between the build image and the
build container. The build image is a pre-built set of commands and
configuration layers used to save time when starting a container. The build
image is constructed using a `Dockerfile` and is configued by the
`build-container.sh` script. This is run automatically by `build-ceph.sh` so
unless you're working on the build image you don't normally need to run it yourself.

The image build process is aggressively cached by Docker, so if there are no
changes the image build is really quick and can be safely run every time.
However, knowing what constitutes a 'change' in this context can be subtle; we'll speak more of this later.

A container is where actual Ceph builds are performed. It's the job of the
build image to cache as much up-front work as we can, so repeated builds can
be started as quickly as possible, but each time with a clean OS environment
regardless of the host you're running on. This is what makes container builds
so useful - they allow every user to have identical build environments
everywhere they're used, with very little effort.

The build image installs a basic OS environment, builds from source some
things we need, and then runs Ceph's _very_ slow `install-deps.sh` script in
the build image so we don't have to do it every time. Note that the build
image can't mount volumes from the host, and by design doesn't (without extra
effort) inherit environment variables etc. from the caller.

The container starts where the build image ends. In this environment, the
container mounts some volumes (including the ccache directory and the Ceph
source working copy), then by default runs a build script that knows how to
build Ceph itself. Every time you run the container you get a fresh start. This might confuse initially but actually is a real benefit once you're
used to it.

Note, however, that we're mounting the source code into the container, so
anything you change in the source tree you mount in will persist after the
container has stopped. For example, a Debian build will *wipe* any deviations
from the working copy as seen by Git. Commit your changes before doing a
Debian build!

#### Details of the build process.

The container build takes a long time if building from scratch. The best thing
to do is try to keep things that change infrequently but take a long time to
the 'top' of the Dockerfile, so that fewer large layers need to be built.

This is complicated by the fact that later stages of the container build are
actually Ceph version-dependent, as explained above.

The current practice is to construct a two-stage build image. The first stage
`deps` installs enough software to install all our custom dependencies into
known directories. The second stage `build` copies the outputs of those builds
into the final build image. This isn't necessary, but it's neater - the build
stage can evolve away from the deps stage as much as it likes, as long as it
doesn't change anything about how the custom deps are built, and the huge
compilation steps can be skipped.

However, if you change the deps stage in the Dockerfile or anything in the
`build/` directory, the deps stage will be rebuilt too.

#### <a name='Binarydependencycompilationandinstall'></a>Binary dependency compilation and install

Scripts in `build/` are run to configure various dependencies. Most are
configured via `config.env`.

| Script | Tool | Used by | Notes |
| - | - | - | -|
| `ccache.sh` | ccache | | Compilation cache tool. |
| `abseil.sh` | abseil-cpp | gRPC, OpenTelemetry | Google C++ utility library. |
| `golang.sh` | The Go language | The Ceph build CMake | Golang itself. |
|| `buf` | The Ceph build CMake | Used to manage protocol buffer code generation. |
| `grpc.sh` | grpc | The Ceph build CMake | Google gRPC C++ libraries and tools. |
| `openssl3.sh` | OpenSSL 3.x | Nothing yet | A recent version of OpenSSL. |

These are scripts that can do anything in the build environment. If we at some
point decide to use e.g. Artifactory for the binaries for these things, the
scripts can use the cli tools to pull them into the build image here.

#### <a name='install-deps.shandmultipleversions'></a>`install-deps.sh` and multiple versions

`install-deps.sh` varies from release to release and we have to have the
appropriate version in the build image. My solution is to checksum everything
from the source that we need, and use that checksum as the tag to the Docker
build image. Then, when the builder goes to compile the source, it constructs
the same checksum and selects the appropriate Docker image.

This way, if we have two builds with different versions of Ceph, the build
scripts will automatically select the correct image, with `install-deps.sh`
pre-run. This is significant; the deps installer script is very slow, and for
an incremental build cycle it would be an intolerable nuisance.

The build image is configured to run a source build script by default.

#### <a name='install-deps.shspeedhack'></a>`install-deps.sh` speed hack

If you find yourself running the `install-deps.sh` script often, perhaps
because you're working on the image itself, you can speed this up *a lot* by
having an HTTP proxy and pointing it at that. The Debian packages are very
cacheable and after a single normal speed run they will in future come at line
speed from the local proxy. I configure this using `~/.docker/config.json`:

```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://proxy.mydomain.com:3128",
      "httpsProxy": "http://proxy.mydomain.com:3128",
      "noProxy": "*.mydomain.com,127.0.0.0/8"
    }
  }
}
```

### <a name='build-ceph.sh-thebuildscript.'></a>`build-ceph.sh` - the build script.

The build script takes a few command line options, but essentially runs either
a source build (`./do-cmake.sh && ... && ninja`) or a Debian build
(`./make-debs.sh` or `dpkg-buildpackage`).

By design the script is opinionated in how it builds. However, you can pass as
many `-c` options (to specify CMake options) to the build script as you like,
as shown in the examples above.

#### <a name='Poweroptions'></a>Power options

You can tweak how dpkg-buildpackage operates by using the `-O` option to
set `DEB_BUILD_OPTIONS`. If you don't know what this does, don't use it.

More powerfully still, you can pass in arbitrary environment variables via
file `tools/env`. These can make substantial differences to the output, and if
you try you can totally break things, so use this sparingly.

### <a name='build-container.sh-thecontainerbuilder'></a>`build-container.sh` - the container builder

This is mostly a wrapper around `docker build`, with some subtleties described
above with regard to running the proper version of `install-deps.sh`.

### <a name='source-build.sh-theCephbuilderscriptinsidethecontainer'></a>`source-build.sh` - the Ceph builder script inside the container

Most of the intelligence of the build is in `tools/source-build.sh`. This is
run from *inside* the container. It's the default `ENTRYPOINT`, which means if
you don't override it, Docker will run this script when a container is started
via `docker run`, and any options passed on the command line will be passed
through to the entrypoint.

(The `-i` option to `build-ceph.sh` overrides the `ENTRYPOINT` to be
`/bin/bash` so you can have an interactive shell instead of running the build
script.)

`source-build.sh` takes many options, but most are fairly niche. The `-h` help
explains what each option does, and the examples above should help.

## <a name='Miscellanea'></a>Miscellanea

### <a name='Whatsthisfor'></a>What's this for?

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


