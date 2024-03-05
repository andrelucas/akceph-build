#!/bin/bash

declare -a results
results=()
failures=0
successes=0

function usage() {
    cat <<EOF >&2
Usage: $0 RELEASEDIR
EOF
    exit 1
}

if [[ -z "$1" ]]; then
    usage
fi

RELEASEDIR="$1"
echo "RELEASEDIR='$RELEASEDIR'"
export RELEASEDIR

tests="$(find test -name 'test_*' -type f)"
for t in $tests; do
    echo -e "\n********** Running $t **********"
    if "$t"; then
        results+=("PASS: $t")
        successes=$((successes + 1))
    else
        results+=("FAIL: $t")
        failures=$((failures + 1))
    fi
done

echo -e "\n********** Results **********"
for r in "${results[@]}"; do
    echo "$r"
done

cat <<EOF
Successes: $successes
Failures: $failures
EOF

if [[ $failures -gt 0 ]]; then
    echo -e "\nFAIL"
    exit 1
fi
echo -e "\nPASS"
exit 0
