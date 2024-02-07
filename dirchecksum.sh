#!/bin/bash

SCRIPTDIR="$(realpath "$(dirname "$0")")"

set -e
# shellcheck source=vars.sh.example
source "$SCRIPTDIR/vars.sh"
source "$SCRIPTDIR/lib.sh"

dir="$1"
if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

hash_dir "$dir"
