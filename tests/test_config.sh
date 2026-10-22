#!/usr/bin/env bash
# test_config.sh - unit tests for scripts/config.sh
set -uo pipefail

# shellcheck source=tests/helpers.sh
source "${BASH_SOURCE[0]%/*}/helpers.sh"
# shellcheck source=scripts/common.sh
source "$REPO_ROOT/scripts/common.sh"
# shellcheck source=scripts/config.sh
source "$REPO_ROOT/scripts/config.sh"

# Resolve relative paths against the temp dir so tests never touch the repo.
SENTINELOPS_HOME="$TEST_TMPDIR"
mkdir -p -- "$TEST_TMPDIR/logs" "$TEST_TMPDIR/reports"

printf 'config.sh\n'

# write_conf NAME  (content on stdin) -> prints the file path
write_conf() {
    local path="$TEST_TMPDIR/$1"
    cat > "$path"
    printf '%s' "$path"
}

# load FILE -> sets LOAD_STATUS and ERRORS (all error messages, one per line)
load() {
    config_load "$1"
    LOAD_STATUS=$?
    local IFS=$'\n'
    ERRORS="${SO_CONFIG_ERRORS[*]}"
}

# --- valid configurations ---
load "$REPO_ROOT/config/sentinelops.conf.example"
assert_eq 0 "$LOAD_STATUS" "the shipped example configuration is valid"

load ""
assert_eq 0 "$LOAD_STATUS" "built-in defaults are valid"
assert_eq 80 "$(config_get CPU_WARNING)" "default CPU_WARNING is 80"

conf="$(write_conf comments_only.conf <<'EOF'
# only comments

   # indented comment
EOF
)"
load "$conf"
assert_eq 0 "$LOAD_STATUS" "a file with only comments and blank lines is valid"

conf="$(write_conf override.conf <<'EOF'
CPU_WARNING=70
  CPU_CRITICAL = 95
ENABLE_NETWORK=false
EOF
)"
load "$conf"
assert_eq 0 "$LOAD_STATUS" "overrides with surrounding whitespace load"
assert_eq "70 95" "$(config_get CPU_WARNING) $(config_get CPU_CRITICAL)" "overridden thresholds are applied"
assert_eq 90 "$(config_get MEMORY_CRITICAL)" "keys not in the file keep their defaults"
assert_true "config_is_true is false for ENABLE_NETWORK=false" eval '! config_is_true ENABLE_NETWORK'
assert_true "config_is_true is true for a default-true key" config_is_true ENABLE_CPU

printf 'CPU_WARNING=75' > "$TEST_TMPDIR/no_newline.conf"
load "$TEST_TMPDIR/no_newline.conf"
assert_eq "0 75" "$LOAD_STATUS $(config_get CPU_WARNING)" "a last line without a trailing newline is read"

printf 'CPU_WARNING=75\r\nDISK_WARNING=60\r\n' > "$TEST_TMPDIR/crlf.conf"
load "$TEST_TMPDIR/crlf.conf"
assert_eq "0 75 60" "$LOAD_STATUS $(config_get CPU_WARNING) $(config_get DISK_WARNING)" \
    "Windows (CRLF) line endings are handled"

# --- invalid values are rejected ---
expect_invalid() {  # expect_invalid DESCRIPTION EXPECTED_ERROR_FRAGMENT CONTENT
    local conf
    conf="$(printf '%s\n' "$3" | write_conf invalid.conf)"
    load "$conf"
    if [[ "$LOAD_STATUS" -ne 0 && "$ERRORS" == *"$2"* ]]; then
        _pass "$1"
    else
        _fail "$1" "status: $LOAD_STATUS" "errors: ${ERRORS@Q}" "expected fragment: ${2@Q}"
    fi
}

expect_invalid "non-numeric threshold" "CPU_WARNING must be an integer" "CPU_WARNING=high"
expect_invalid "threshold above 100" "CPU_CRITICAL must be an integer" "CPU_CRITICAL=101"
expect_invalid "negative threshold" "DISK_WARNING must be an integer" "DISK_WARNING=-5"
expect_invalid "decimal threshold" "MEMORY_WARNING must be an integer" "MEMORY_WARNING=80.5"
expect_invalid "leading zero (would be octal in Bash)" "CPU_WARNING must be an integer" "CPU_WARNING=080"
expect_invalid "empty threshold" "CPU_WARNING must be an integer" "CPU_WARNING="
expect_invalid "inline comment after value" "CPU_WARNING must be an integer" "CPU_WARNING=80 # note"
expect_invalid "warning equal to critical" "CPU_WARNING (90) must be lower than CPU_CRITICAL (90)" "CPU_WARNING=90"
expect_invalid "warning above critical" "DISK_WARNING (95) must be lower than DISK_CRITICAL (90)" "DISK_WARNING=95"
expect_invalid "interval of zero" "CHECK_INTERVAL must be an integer from 1" "CHECK_INTERVAL=0"
expect_invalid "interval too large" "CHECK_INTERVAL must be an integer from 1" "CHECK_INTERVAL=86401"
expect_invalid "bool 'yes'" "ENABLE_CPU must be 'true' or 'false'" "ENABLE_CPU=yes"
expect_invalid "bool in wrong case" "ENABLE_DISK must be 'true' or 'false'" "ENABLE_DISK=True"
expect_invalid "unknown key (typo)" "unknown key 'CPU_WARNNG'" "CPU_WARNNG=80"
expect_invalid "lowercase key" "unknown key 'cpu_warning'" "cpu_warning=80"
expect_invalid "duplicate key" "duplicate key 'CPU_WARNING' (first set on line 1)" $'CPU_WARNING=70\nCPU_WARNING=75'
expect_invalid "line without '='" "malformed line" "just some words"
expect_invalid "unbalanced quote" "unbalanced quotes" 'LOG_DIRECTORY="./logs'
expect_invalid "empty path" "LOG_DIRECTORY must not be empty" 'LOG_DIRECTORY=""'
expect_invalid "list with ',,'" "empty item" "MONITORED_PROCESSES=sshd,,cron"
expect_invalid "list with trailing comma" "trailing comma" "MONITORED_PROCESSES=sshd,"
expect_invalid "list item with shell metacharacters" "invalid characters" "MONITORED_SERVICES=ssh;reboot"
expect_invalid "list item that looks like an option" "invalid characters" "MONITORED_PROCESSES=-9"

# Errors include the file and line number.
conf="$(printf '# c\nCPU_WARNING=bad\n' | write_conf lineno.conf)"
load "$conf"
assert_contains "lineno.conf:2: CPU_WARNING" "$ERRORS" "errors report file and line number"

# All problems are reported, not just the first.
conf="$(printf 'CPU_WARNING=x\nENABLE_CPU=maybe\nNOPE=1\n' | write_conf multi.conf)"
load "$conf"
assert_eq 3 "${#SO_CONFIG_ERRORS[@]}" "every error in a file is reported in one run"

# --- the config file is never executed ---
marker="$TEST_TMPDIR/PWNED"
conf="$(write_conf injection.conf <<EOF
CPU_WARNING=\$(touch $marker)
MEMORY_WARNING=\`touch $marker\`
LOG_DIRECTORY=\$(touch $marker)
touch $marker
EOF
)"
load "$conf"
assert_true "command substitution in the config is not executed" test ! -e "$marker"
assert_eq 1 "$LOAD_STATUS" "a config containing shell code is rejected"

# --- file problems ---
load "$TEST_TMPDIR/does-not-exist.conf"
assert_contains "does not exist" "$ERRORS" "a missing config file is an error"

load "$TEST_TMPDIR"
assert_contains "is a directory" "$ERRORS" "a directory as config file is an error"

load /dev/null
assert_contains "not a regular file" "$ERRORS" "a device as config file is an error"

if (( EUID != 0 )); then
    conf="$(printf 'CPU_WARNING=70\n' | write_conf unreadable.conf)"
    chmod 000 "$conf"
    load "$conf"
    assert_contains "not readable" "$ERRORS" "an unreadable config file is an error"
    chmod 600 "$conf"
else
    skip "unreadable config file (running as root, permissions are not enforced)"
fi

# --- paths ---
mkdir -p -- "$TEST_TMPDIR/my logs"
conf="$(printf 'LOG_DIRECTORY="./my logs"\n' | write_conf spaces.conf)"
load "$conf"
assert_eq "0 $TEST_TMPDIR/my logs" "$LOAD_STATUS $(config_get LOG_DIRECTORY)" \
    "a relative path with spaces resolves against the project root"

conf="$(printf 'REPORT_DIRECTORY=%s\n' "$TEST_TMPDIR/reports" | write_conf abs.conf)"
load "$conf"
assert_eq "$TEST_TMPDIR/reports" "$(config_get REPORT_DIRECTORY)" "an absolute path is kept as is"

touch "$TEST_TMPDIR/a-file"
conf="$(printf 'LOG_DIRECTORY=./a-file\n' | write_conf notdir.conf)"
load "$conf"
assert_contains "is not a directory" "$ERRORS" "a path that is a regular file is an error"

conf="$(printf 'LOG_DIRECTORY=./not-created\n' | write_conf missingdir.conf)"
load "$conf"
assert_eq 0 "$LOAD_STATUS" "a directory that does not exist yet is not an error"
assert_contains "does not exist yet" "${SO_CONFIG_WARNINGS[*]}" "... but it produces a warning"

# --- lists ---
conf="$(printf 'MONITORED_PROCESSES= sshd , cron,python3 \n' | write_conf list.conf)"
load "$conf"
assert_eq "sshd,cron,python3" "$(config_get MONITORED_PROCESSES)" "list items are trimmed and normalised"
mapfile -t procs < <(config_get_list MONITORED_PROCESSES)
assert_eq "3:sshd:python3" "${#procs[@]}:${procs[0]}:${procs[2]}" "config_get_list prints one item per line"

conf="$(printf 'MONITORED_SERVICES=\n' | write_conf emptylist.conf)"
load "$conf"
mapfile -t svcs < <(config_get_list MONITORED_SERVICES)
assert_eq "0 0" "$LOAD_STATUS ${#svcs[@]}" "an empty list is valid and has no items"

# --- accessors ---
assert_true "config_get fails for an unknown key" eval '! config_get NOT_A_KEY'

test_summary
