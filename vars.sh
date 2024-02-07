# shellcheck shell=bash

export CCACHE_DIR=$HOME/.ccache
# Make CCACHE_CONF under CCACHE_DIR or you'll confuse matters.
export CCACHE_CONF=$CCACHE_DIR/ccache.conf
export CEPH_SRC=~/git/ceph
export DOCKER=docker
export IMAGE=cbuild:latest
export TOOLS_SRC="$PWD/tools"

export C_CCACHE=/ccache
export C_SRC=/src
export C_TOOLS=/tools
