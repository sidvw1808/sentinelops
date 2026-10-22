#!/usr/bin/env bash
# common.sh - shared logging, error and dependency helpers for SentinelOps.
#
# This file is a library: source it, do not execute it. It deliberately does
# not run `set -e`, `set -u` or `set -o pipefail`, because shell options set in
# a sourced file change the behaviour of whoever sourced it. The caller decides.
#
# All log output goes to stderr (file descriptor 2) so that stdout stays clean
# for real program output such as reports and JSON.

# Sourcing twice would try to redefine the readonly variables below and fail.
if [[ -n "${_SO_COMMON_LOADED:-}" ]]; then
    return 0
fi
_SO_COMMON_LOADED=1

# Exit codes (see README "Exit codes"). Used by the scripts that source this.
# shellcheck disable=SC2034  # used by files that source common.sh
readonly SO_EXIT_OK=0          # ran fine, nothing wrong found
# shellcheck disable=SC2034
readonly SO_EXIT_PROBLEM=1     # ran fine, WARNING or CRITICAL found
# shellcheck disable=SC2034
readonly SO_EXIT_USAGE=2       # invalid arguments or configuration
# shellcheck disable=SC2034
readonly SO_EXIT_FAILURE=3     # monitoring failed / data could not be collected

# Numeric value for each log level. A message is printed when its level is
# greater than or equal to the threshold in SENTINELOPS_LOG_LEVEL.
# `declare -g` keeps the array global even if this file is sourced from inside
# a function (plain `declare` would make it local to that function).
declare -grA _SO_LOG_LEVELS=([DEBUG]=10 [INFO]=20 [WARN]=30 [ERROR]=40)

# log_level_is_valid LEVEL
# Returns 0 if LEVEL is one of DEBUG, INFO, WARN, ERROR.
log_level_is_valid() {
    [[ -n "${1:-}" && -n "${_SO_LOG_LEVELS[$1]:-}" ]]
}

# _so_use_color
# Colour only when stderr is a terminal, NO_COLOR is unset (https://no-color.org)
# and the terminal is not "dumb". Redirected output never contains escape codes.
_so_use_color() {
    [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]
}

# log_msg LEVEL MESSAGE...
# Writes one line to stderr: "<UTC timestamp> [LEVEL] sentinelops: MESSAGE".
# An unknown or unset SENTINELOPS_LOG_LEVEL falls back to INFO.
log_msg() {
    local level="${1:-INFO}"
    shift

    log_level_is_valid "$level" || level="ERROR"

    local threshold="${SENTINELOPS_LOG_LEVEL:-INFO}"
    log_level_is_valid "$threshold" || threshold="INFO"

    if (( _SO_LOG_LEVELS[$level] < _SO_LOG_LEVELS[$threshold] )); then
        return 0
    fi

    # printf's %(...)T formats the time without forking `date`.
    # The TZ=UTC prefix applies only to this one command.
    local timestamp
    TZ=UTC printf -v timestamp '%(%Y-%m-%dT%H:%M:%SZ)T' -1

    local tag="[$level]"
    if _so_use_color; then
        local color
        case "$level" in
            DEBUG) color=$'\e[2m' ;;   # dim
            INFO)  color=$'\e[36m' ;;  # cyan
            WARN)  color=$'\e[33m' ;;  # yellow
            ERROR) color=$'\e[31m' ;;  # red
        esac
        tag="${color}${tag}"$'\e[0m'
    fi

    # "$*" joins all message arguments with single spaces.
    printf '%s %s sentinelops: %s\n' "$timestamp" "$tag" "$*" >&2
}

log_debug() { log_msg DEBUG "$@"; }
log_info()  { log_msg INFO "$@"; }
log_warn()  { log_msg WARN "$@"; }
log_error() { log_msg ERROR "$@"; }

# die EXIT_CODE MESSAGE...
# Logs MESSAGE as an error and exits the WHOLE program with EXIT_CODE.
# Only call this from top-level CLI code. Monitoring modules must return a
# status instead, so one failing module cannot stop the others.
die() {
    local code="${1:-$SO_EXIT_FAILURE}"
    shift
    log_error "$@"
    exit "$code"
}

# has_cmd NAME
# Returns 0 if NAME is an available command (builtin, function or on PATH).
has_cmd() {
    command -v -- "${1:-}" >/dev/null 2>&1
}

# systemd_is_running
# Returns 0 if systemd is the running init system. Having `systemctl` installed
# is not enough: on WSL2 without systemd enabled the binary exists but cannot
# talk to a service manager. /run/systemd/system exists only when systemd
# booted the system (the same test sd_booted(3) uses).
systemd_is_running() {
    [[ -d /run/systemd/system ]]
}

# json_escape STRING
# Prints STRING escaped for use inside a JSON string literal (RFC 8259):
# backslash, double quote and all control characters U+0000..U+001F.
json_escape() {
    local s="${1-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"

    # Any remaining control character becomes \u00XX. (Bash strings cannot
    # contain NUL, so the loop starts at 1.)
    local i hex ch
    for (( i = 1; i < 32; i++ )); do
        printf -v hex '%02x' "$i"
        printf -v ch '%b' "\\x$hex"
        if [[ "$s" == *"$ch"* ]]; then
            s="${s//"$ch"/\\u00$hex}"
        fi
    done

    printf '%s' "$s"
}
