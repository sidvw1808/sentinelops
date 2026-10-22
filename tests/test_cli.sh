#!/usr/bin/env bash
# test_cli.sh - integration tests for sentinelops.sh (commands, options, exit codes)
set -uo pipefail

# shellcheck source=tests/helpers.sh
source "${BASH_SOURCE[0]%/*}/helpers.sh"

printf 'sentinelops.sh\n'

EXAMPLE="$REPO_ROOT/config/sentinelops.conf.example"
CLI_ENV=()

# --- help and version ---
run_cli --help
assert_eq 0 "$RUN_STATUS" "--help exits 0"
assert_contains "Usage:" "$RUN_STDOUT" "--help prints usage to stdout"
assert_contains "Exit codes:" "$RUN_STDOUT" "--help documents exit codes"

run_cli help
assert_eq 0 "$RUN_STATUS" "'help' command exits 0"

run_cli
assert_eq 2 "$RUN_STATUS" "no command exits 2"
assert_eq "" "$RUN_STDOUT" "no command prints usage to stderr, not stdout"

run_cli version
assert_match '^sentinelops [0-9]+\.[0-9]+\.[0-9]+$' "$RUN_STDOUT" "version prints 'sentinelops X.Y.Z'"
assert_eq 0 "$RUN_STATUS" "version exits 0"

run_cli --json version
assert_json_valid "$RUN_STDOUT" "--json version prints valid JSON"

# --- argument errors (exit 2, never silently ignored) ---
run_cli frobnicate
assert_eq 2 "$RUN_STATUS" "an unknown command exits 2"
assert_contains "unknown command" "$RUN_STDERR" "an unknown command is explained on stderr"

run_cli --frobnicate version
assert_eq 2 "$RUN_STATUS" "an unknown option exits 2"

run_cli version extra
assert_eq 2 "$RUN_STATUS" "an extra positional argument exits 2"

run_cli validate-config --config
assert_eq 2 "$RUN_STATUS" "--config without a value exits 2"

run_cli validate-config --config ""
assert_eq 2 "$RUN_STATUS" "--config with an empty value exits 2"

run_cli validate-config -c "$EXAMPLE" -c "$EXAMPLE"
assert_eq 2 "$RUN_STATUS" "--config given twice exits 2"

run_cli version --module cpu
assert_eq 2 "$RUN_STATUS" "--module with a command other than check exits 2"

run_cli check --module bogus --config "$EXAMPLE"
assert_eq 2 "$RUN_STATUS" "an unknown module exits 2"

run_cli --json deps
assert_eq 2 "$RUN_STATUS" "--json with a command that does not support it exits 2"

run_cli -v -q version
assert_eq 2 "$RUN_STATUS" "--verbose with --quiet exits 2"

run_cli report
assert_eq 2 "$RUN_STATUS" "a planned but unimplemented command exits 2"

# --- validate-config ---
run_cli validate-config --config "$EXAMPLE"
assert_eq 0 "$RUN_STATUS" "validate-config accepts the example config"
assert_contains "Configuration valid" "$RUN_STDOUT" "validate-config reports success on stdout"

run_cli --config="$EXAMPLE" validate-config
assert_eq 0 "$RUN_STATUS" "--config=PATH form works before the command"

printf 'CPU_WARNING=95\nENABLE_CPU=maybe\n' > "$TEST_TMPDIR/bad.conf"
run_cli validate-config --config "$TEST_TMPDIR/bad.conf"
assert_eq 2 "$RUN_STATUS" "validate-config rejects an invalid config with exit 2"
assert_contains "ENABLE_CPU must be 'true' or 'false'" "$RUN_STDERR" "validation errors are shown on stderr"

run_cli --json validate-config --config "$TEST_TMPDIR/bad.conf"
assert_json_valid "$RUN_STDOUT" "--json validate-config prints valid JSON for an invalid config"
assert_contains '"valid":false' "$RUN_STDOUT" "JSON reports valid:false"

run_cli validate-config --config "$TEST_TMPDIR/missing.conf"
assert_eq 2 "$RUN_STATUS" "an explicit config path that does not exist exits 2"

CLI_ENV=("SENTINELOPS_CONFIG=$TEST_TMPDIR/bad.conf")
run_cli validate-config
assert_eq 2 "$RUN_STATUS" "SENTINELOPS_CONFIG is used when --config is not given"
run_cli validate-config --config "$EXAMPLE"
assert_eq 0 "$RUN_STATUS" "--config takes precedence over SENTINELOPS_CONFIG"
CLI_ENV=()

# --- built-in defaults: run a private copy so a developer's own
#     config/sentinelops.conf cannot influence the result ---
install_dir="$TEST_TMPDIR/install"
mkdir -p -- "$install_dir/scripts"
cp -- "$REPO_ROOT/sentinelops.sh" "$install_dir/"
cp -- "$REPO_ROOT/scripts/"*.sh "$install_dir/scripts/"
CLI_SCRIPT="$install_dir/sentinelops.sh"
run_cli validate-config
assert_eq 0 "$RUN_STATUS" "without any config file, built-in defaults are valid"
assert_contains "using built-in defaults" "$RUN_STDERR" "... and a warning says defaults are used"
unset CLI_SCRIPT

# --- check never reports healthy without measurements ---
run_cli check --config "$EXAMPLE"
assert_eq 3 "$RUN_STATUS" "check exits 3 while no module can collect data"
assert_contains "Overall status: UNKNOWN" "$RUN_STDOUT" "check reports overall UNKNOWN"
assert_not_contains "[OK]" "$RUN_STDOUT" "check never prints OK without a measurement"

run_cli check --module disk --config "$EXAMPLE"
assert_contains "[UNKNOWN] disk" "$RUN_STDOUT" "check --module runs the requested module"
assert_not_contains "cpu" "$RUN_STDOUT" "check --module does not run other modules"

all_off="$TEST_TMPDIR/all_off.conf"
for key in CPU MEMORY DISK PROCESS SERVICES NETWORK LOG_ANALYSIS; do
    printf 'ENABLE_%s=false\n' "$key"
done > "$all_off"
run_cli check --config "$all_off"
assert_eq 3 "$RUN_STATUS" "check with every module disabled exits 3, not 0"

run_cli check --config "$TEST_TMPDIR/bad.conf"
assert_eq 2 "$RUN_STATUS" "check with an invalid config exits 2"

# --- logging behaviour ---
run_cli --quiet check --config "$EXAMPLE"
assert_not_contains "[WARN]" "$RUN_STDERR" "--quiet hides warnings"

run_cli --verbose validate-config --config "$EXAMPLE"
assert_contains "[DEBUG]" "$RUN_STDERR" "--verbose shows debug messages"

CLI_ENV=(SENTINELOPS_LOG_LEVEL=LOUD)
run_cli version
assert_contains "ignoring invalid SENTINELOPS_LOG_LEVEL" "$RUN_STDERR" "an invalid SENTINELOPS_LOG_LEVEL is reported"
CLI_ENV=()

# --- dependency checks, using a PATH that contains only chosen tools ---
# make_bin DIR CMD...  -> DIR containing symlinks to the real CMDs
make_bin() {
    local dir="$1" cmd real
    shift
    mkdir -p -- "$dir"
    for cmd in "$@"; do
        real="$(command -v -- "$cmd")" && ln -sf -- "$real" "$dir/$cmd"
    done
}

make_bin "$TEST_TMPDIR/bin-required" awk grep sed df ps
CLI_ENV=("PATH=$TEST_TMPDIR/bin-required")
run_cli deps
assert_eq 0 "$RUN_STATUS" "deps exits 0 when only optional tools are missing"
assert_contains "optional command 'curl' not found" "$RUN_STDERR" "a missing optional tool is reported as a warning"

make_bin "$TEST_TMPDIR/bin-no-awk" grep sed df ps
CLI_ENV=("PATH=$TEST_TMPDIR/bin-no-awk")
run_cli deps
assert_eq 3 "$RUN_STATUS" "deps exits 3 when a required tool is missing"
assert_contains "required command 'awk' not found" "$RUN_STDERR" "the missing required tool is named"

CLI_ENV=("PATH=$TEST_TMPDIR/bin-no-awk")
run_cli version
assert_eq 0 "$RUN_STATUS" "the CLI starts even when tools are missing"
CLI_ENV=()

test_summary
