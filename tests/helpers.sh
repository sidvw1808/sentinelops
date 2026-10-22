#!/usr/bin/env bash
# helpers.sh - minimal assertion helpers for the SentinelOps test suite.
#
# Source this from a test file, write tests with the assert_* functions, and
# finish with `test_summary`. Each test file gets its own temporary directory
# ($TEST_TMPDIR) that is removed automatically when the file exits.

REPO_ROOT="$(cd -P -- "${BASH_SOURCE[0]%/*}/.." && pwd)"
readonly REPO_ROOT

# Do not let the developer's own environment change test results.
unset SENTINELOPS_CONFIG SENTINELOPS_LOG_LEVEL NO_COLOR

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/sentinelops-test.XXXXXX")" || {
    printf 'cannot create temporary directory\n' >&2
    exit 1
}
readonly TEST_TMPDIR

_cleanup_test_tmpdir() {
    # Only ever remove the directory mktemp created for us.
    if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" && "$TEST_TMPDIR" == */sentinelops-test.* ]]; then
        rm -rf -- "$TEST_TMPDIR"
    fi
}
trap _cleanup_test_tmpdir EXIT

TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0

_pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf '  ok    %s\n' "$1"
}

_fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL  %s\n' "$1"
    shift
    local detail
    for detail in "$@"; do
        printf '          %s\n' "$detail"
    done
}

skip() {
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    printf '  skip  %s\n' "$1"
}

# assert_eq EXPECTED ACTUAL DESCRIPTION
assert_eq() {
    if [[ "$1" == "$2" ]]; then
        _pass "$3"
    else
        _fail "$3" "expected: ${1@Q}" "actual:   ${2@Q}"
    fi
}

# assert_match REGEX ACTUAL DESCRIPTION
assert_match() {
    if [[ "$2" =~ $1 ]]; then
        _pass "$3"
    else
        _fail "$3" "regex:  $1" "actual: ${2@Q}"
    fi
}

# assert_contains NEEDLE HAYSTACK DESCRIPTION
assert_contains() {
    if [[ "$2" == *"$1"* ]]; then
        _pass "$3"
    else
        _fail "$3" "expected to contain: ${1@Q}" "actual: ${2@Q}"
    fi
}

# assert_not_contains NEEDLE HAYSTACK DESCRIPTION
assert_not_contains() {
    if [[ "$2" != *"$1"* ]]; then
        _pass "$3"
    else
        _fail "$3" "expected NOT to contain: ${1@Q}" "actual: ${2@Q}"
    fi
}

# assert_true DESCRIPTION COMMAND...
# Passes if COMMAND exits 0.
assert_true() {
    local desc="$1"
    shift
    if "$@"; then
        _pass "$desc"
    else
        _fail "$desc" "command failed: $*"
    fi
}

# run_cli ARGS...
# Runs sentinelops.sh with ARGS. Sets RUN_STATUS, RUN_STDOUT and RUN_STDERR.
# Set CLI_ENV (array of NAME=value) to run with extra environment variables,
# and CLI_SCRIPT to run a different copy of sentinelops.sh.
run_cli() {
    local script="${CLI_SCRIPT:-$REPO_ROOT/sentinelops.sh}"
    local out="$TEST_TMPDIR/.stdout" err="$TEST_TMPDIR/.stderr"
    env ${CLI_ENV[@]+"${CLI_ENV[@]}"} "$BASH" "$script" "$@" >"$out" 2>"$err"
    RUN_STATUS=$?
    RUN_STDOUT="$(<"$out")"
    RUN_STDERR="$(<"$err")"
}

# json_is_valid STRING
# Returns 0 if STRING is valid JSON, 1 if not, 2 if no validator is installed.
json_is_valid() {
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$1" | python3 -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null
    elif command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -e . >/dev/null 2>&1
    else
        return 2
    fi
}

# assert_json_valid STRING DESCRIPTION
assert_json_valid() {
    json_is_valid "$1"
    case $? in
        0) _pass "$2" ;;
        2) skip "$2 (no python3 or jq to validate JSON)" ;;
        *) _fail "$2" "invalid JSON: ${1@Q}" ;;
    esac
}

# test_summary
# Prints the result line and exits non-zero if any test failed.
test_summary() {
    printf '  -- %d run, %d failed, %d skipped\n' "$TESTS_RUN" "$TESTS_FAILED" "$TESTS_SKIPPED"
    (( TESTS_FAILED == 0 ))
    exit $?
}
