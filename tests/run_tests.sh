#!/usr/bin/env bash
# run_tests.sh - run every tests/test_*.sh file and summarise the results.
#
# Usage: tests/run_tests.sh [TEST_FILE...]
# Exit status: 0 if every test file passed, 1 otherwise.
set -uo pipefail

tests_dir="$(cd -P -- "${BASH_SOURCE[0]%/*}" && pwd)"

if (( $# > 0 )); then
    files=("$@")
else
    files=("$tests_dir"/test_*.sh)
fi

failed=()
for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        printf 'no such test file: %s\n' "$file" >&2
        failed+=("$file")
        continue
    fi
    if ! "$BASH" "$file"; then
        failed+=("${file##*/}")
    fi
    printf '\n'
done

if (( ${#failed[@]} > 0 )); then
    printf 'FAILED: %s\n' "${failed[*]}"
    exit 1
fi
printf 'All %d test files passed.\n' "${#files[@]}"
