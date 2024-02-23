#!/bin/bash

uid="$(id -u)"

sudo=""
if [[ $uid -ne 0 ]]; then
    sudo="sudo"
    echo "Will use sudo(1), may prompt for password"
fi

set -e -x
$sudo rm -rf tmp.*
$sudo rm -rf preinstall*
$sudo rm -rf release_*
$sudo find release -mindepth 1 -delete
git checkout release/
