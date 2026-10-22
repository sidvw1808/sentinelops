#!/usr/bin/env bash
# test_common.sh - unit tests for scripts/common.sh
set -uo pipefail

# shellcheck source=tests/helpers.sh
source "${BASH_SOURCE[0]%/*}/helpers.sh"
# shellcheck source=scripts/common.sh
source "$REPO_ROOT/scripts/common.sh"

printf 'common.sh\n'

# --- logging goes to stderr only ---
stdout="$(log_info "hello" 2>/dev/null)"
stderr="$(log_info "hello" 2>&1 >/dev/null)"
assert_eq "" "$stdout" "log_info writes nothing to stdout"
assert_contains "[INFO] sentinelops: hello" "$stderr" "log_info writes the message to stderr"
assert_match '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ' "$stderr" \
    "log line starts with a UTC ISO-8601 timestamp"

stderr="$(log_info "two" "words" 2>&1)"
assert_contains "sentinelops: two words" "$stderr" "multiple arguments are joined with spaces"

# --- level filtering ---
stderr="$(log_debug "hidden" 2>&1)"
assert_eq "" "$stderr" "DEBUG is hidden at the default level (INFO)"

stderr="$(SENTINELOPS_LOG_LEVEL=DEBUG log_debug "shown" 2>&1)"
assert_contains "[DEBUG]" "$stderr" "DEBUG is shown when SENTINELOPS_LOG_LEVEL=DEBUG"

stderr="$(SENTINELOPS_LOG_LEVEL=ERROR log_warn "hidden" 2>&1)"
assert_eq "" "$stderr" "WARN is hidden when SENTINELOPS_LOG_LEVEL=ERROR"

stderr="$(SENTINELOPS_LOG_LEVEL=nonsense log_info "shown" 2>&1)"
assert_contains "[INFO]" "$stderr" "an invalid SENTINELOPS_LOG_LEVEL falls back to INFO"

stderr="$(log_msg BOGUS "msg" 2>&1)"
assert_contains "[ERROR]" "$stderr" "an unknown message level is treated as ERROR (never dropped)"

# --- no colour when stderr is not a terminal ---
stderr="$(log_error "plain" 2>&1)"
assert_not_contains $'\e' "$stderr" "no ANSI escape codes when stderr is redirected"

# --- die ---
( die 7 "fatal" ) 2>/dev/null
assert_eq 7 "$?" "die exits with the given code"

# --- has_cmd ---
assert_true "has_cmd finds bash" has_cmd bash
assert_true "has_cmd does not find a nonexistent command" \
    eval '! has_cmd sentinelops-no-such-command-xyz'

# --- json_escape ---
assert_eq 'a\"b' "$(json_escape 'a"b')" "json_escape escapes double quotes"
assert_eq 'a\\b' "$(json_escape 'a\b')" "json_escape escapes backslashes"
assert_eq 'a\nb\tc' "$(json_escape $'a\nb\tc')" "json_escape escapes newline and tab"
assert_eq 'a\u001bb' "$(json_escape $'a\eb')" "json_escape escapes other control characters as \\u00XX"
assert_eq 'plain text' "$(json_escape 'plain text')" "json_escape leaves ordinary text alone"
assert_json_valid "\"$(json_escape $'quote" back\\ nl\n esc\e')\"" "json_escape output forms a valid JSON string"

# --- the library must not change the caller's shell options ---
opts="$("$BASH" -c 'source "$1"; printf "%s" "$-"' _ "$REPO_ROOT/scripts/common.sh")"
assert_not_contains "e" "$opts" "sourcing common.sh does not enable errexit"
assert_not_contains "u" "$opts" "sourcing common.sh does not enable nounset"

# --- double sourcing is harmless ---
assert_true "common.sh can be sourced twice" source "$REPO_ROOT/scripts/common.sh"

test_summary
