#!/usr/bin/env bash
# sentinelops.sh - SentinelOps command-line entry point.
#
# Run `./sentinelops.sh --help` for usage. See README.md for details.

# The libraries use associative arrays and `declare -g`, which need Bash 4.2+;
# the project targets 4.4+. Check first, using only old-Bash syntax, so users
# of an older Bash get a clear message instead of confusing syntax errors.
if [ -z "${BASH_VERSINFO:-}" ] ||
   [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    printf 'sentinelops: Bash 4.4 or newer is required (found %s)\n' "${BASH_VERSION:-unknown}" >&2
    exit 3
fi

# -u: using an unset variable is an error (catches typos).
# -o pipefail: a pipeline fails if any command in it fails, not just the last.
# No -e: errexit is ignored in many contexts (functions called from `if`,
# `&&` lists, command substitutions) and would make one failing check abort
# the whole run. Errors are handled explicitly instead.
set -uo pipefail

# Locate the project directory, following a symlink to this script (e.g. one
# placed in ~/.local/bin). readlink -f is GNU coreutils; without it, a
# symlinked install is not resolved but a direct run still works.
_so_script="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    _so_script="$(readlink -f -- "$_so_script")"
fi
_so_dir="${_so_script%/*}"
[[ "$_so_dir" == "$_so_script" ]] && _so_dir="."
SENTINELOPS_HOME="$(cd -P -- "$_so_dir" && pwd)" || {
    printf 'sentinelops: cannot determine installation directory\n' >&2
    exit 3
}
readonly SENTINELOPS_HOME
unset _so_script _so_dir

for _so_lib in common.sh config.sh; do
    if [[ ! -r "$SENTINELOPS_HOME/scripts/$_so_lib" ]]; then
        printf 'sentinelops: missing library %s/scripts/%s\n' "$SENTINELOPS_HOME" "$_so_lib" >&2
        exit 3
    fi
done
unset _so_lib
# shellcheck source=scripts/common.sh
source "$SENTINELOPS_HOME/scripts/common.sh"
# shellcheck source=scripts/config.sh
source "$SENTINELOPS_HOME/scripts/config.sh"

readonly SO_VERSION="0.1.0"
readonly SO_PROG="${0##*/}"

# Monitoring modules, and the config key that enables each one.
readonly -a SO_MODULES=(cpu memory disk processes services network logs)
declare -grA SO_MODULE_ENABLE_KEY=(
    [cpu]=ENABLE_CPU
    [memory]=ENABLE_MEMORY
    [disk]=ENABLE_DISK
    [processes]=ENABLE_PROCESS
    [services]=ENABLE_SERVICES
    [network]=ENABLE_NETWORK
    [logs]=ENABLE_LOG_ANALYSIS
)

# External commands the monitoring modules need. Missing any = exit 3.
readonly -a SO_REQUIRED_CMDS=(awk grep sed df ps)
# Optional commands: without them the related feature reports UNKNOWN.
readonly -a SO_OPTIONAL_CMDS=(curl systemctl timeout)
declare -grA SO_OPTIONAL_PURPOSE=(
    [curl]="HTTP endpoint checks (network module)"
    [systemctl]="service checks (services module)"
    [timeout]="time limits for slow checks"
)

# Parsed command-line options (set by parse_args).
OPT_COMMAND=""
OPT_CONFIG=""
OPT_MODULE=""
OPT_JSON=0
OPT_VERBOSE=0
OPT_QUIET=0
OPT_HELP=0

usage() {
    printf '%s\n' "Usage: $SO_PROG [OPTIONS] COMMAND [OPTIONS]

SentinelOps - Bash-based Linux monitoring and incident response toolkit.

Commands:
  check                 Run health checks for all enabled modules
  validate-config       Validate the configuration file and report problems
  deps                  Show which required and optional tools are installed
  version               Print the version
  help                  Show this help

Options (accepted before or after the command):
  -c, --config PATH     Configuration file to use
  -m, --module NAME     With 'check': run only this module
      --json            JSON output (supported by: version, validate-config)
  -v, --verbose         Show debug messages
  -q, --quiet           Show only error messages
  -h, --help            Show this help

Modules:
  ${SO_MODULES[*]}
  Phase 1: no module is implemented yet, so 'check' reports UNKNOWN (exit 3).

Configuration file lookup (first match wins):
  1. --config PATH
  2. \$SENTINELOPS_CONFIG
  3. $SENTINELOPS_HOME/config/sentinelops.conf
  4. built-in defaults (a warning is printed)

Environment:
  SENTINELOPS_CONFIG     Configuration file path
  SENTINELOPS_LOG_LEVEL  DEBUG, INFO (default), WARN or ERROR
  NO_COLOR               Set to disable coloured log output

Exit codes:
  0  success, no problems found
  1  success, but a WARNING or CRITICAL condition was found
  2  invalid arguments or configuration
  3  monitoring failed, or required data/tools were unavailable

Examples:
  $SO_PROG validate-config --config config/sentinelops.conf.example
  $SO_PROG check --module cpu
  $SO_PROG deps"
}

# usage_error MESSAGE
# Reports a command-line mistake. The caller returns SO_EXIT_USAGE.
usage_error() {
    log_error "$*"
    printf "Try '%s --help' for more information.\n" "$SO_PROG" >&2
}

# parse_args ARGS...
# Fills the OPT_* variables. Returns 0 on success, 1 on a usage error.
parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                OPT_HELP=1
                ;;
            -c|--config|--config=*)
                if [[ -n "$OPT_CONFIG" ]]; then
                    usage_error "--config given more than once"
                    return 1
                fi
                if [[ "$1" == --config=* ]]; then
                    OPT_CONFIG="${1#*=}"
                elif (( $# >= 2 )); then
                    OPT_CONFIG="$2"
                    shift
                else
                    usage_error "$1 requires a PATH argument"
                    return 1
                fi
                if [[ -z "$OPT_CONFIG" ]]; then
                    usage_error "--config PATH must not be empty"
                    return 1
                fi
                ;;
            -m|--module|--module=*)
                if [[ -n "$OPT_MODULE" ]]; then
                    usage_error "--module given more than once"
                    return 1
                fi
                if [[ "$1" == --module=* ]]; then
                    OPT_MODULE="${1#*=}"
                elif (( $# >= 2 )); then
                    OPT_MODULE="$2"
                    shift
                else
                    usage_error "$1 requires a module NAME"
                    return 1
                fi
                ;;
            --json)
                OPT_JSON=1
                ;;
            -v|--verbose)
                OPT_VERBOSE=1
                ;;
            -q|--quiet)
                OPT_QUIET=1
                ;;
            -*)
                usage_error "unknown option '$1'"
                return 1
                ;;
            *)
                if [[ -n "$OPT_COMMAND" ]]; then
                    usage_error "unexpected argument '$1' (command '$OPT_COMMAND' already given)"
                    return 1
                fi
                OPT_COMMAND="$1"
                ;;
        esac
        shift
    done

    if (( OPT_VERBOSE && OPT_QUIET )); then
        usage_error "--verbose and --quiet cannot be used together"
        return 1
    fi
    return 0
}

# check_option_compatibility
# Rejects options that make no sense for the chosen command, rather than
# silently ignoring them.
check_option_compatibility() {
    if [[ -n "$OPT_MODULE" && "$OPT_COMMAND" != "check" ]]; then
        usage_error "--module can only be used with 'check'"
        return 1
    fi
    if [[ -n "$OPT_MODULE" ]] && ! is_known_module "$OPT_MODULE"; then
        usage_error "unknown module '$OPT_MODULE' (valid: ${SO_MODULES[*]})"
        return 1
    fi
    if (( OPT_JSON )) && [[ "$OPT_COMMAND" != "version" && "$OPT_COMMAND" != "validate-config" ]]; then
        usage_error "--json is not supported for '$OPT_COMMAND' yet"
        return 1
    fi
    return 0
}

# is_known_module NAME
is_known_module() {
    local m
    for m in "${SO_MODULES[@]}"; do
        [[ "$m" == "$1" ]] && return 0
    done
    return 1
}

# setup_logging
# Applies --verbose / --quiet and sanitises SENTINELOPS_LOG_LEVEL.
setup_logging() {
    if (( OPT_VERBOSE )); then
        SENTINELOPS_LOG_LEVEL=DEBUG
    elif (( OPT_QUIET )); then
        SENTINELOPS_LOG_LEVEL=ERROR
    elif [[ -n "${SENTINELOPS_LOG_LEVEL:-}" ]] && ! log_level_is_valid "$SENTINELOPS_LOG_LEVEL"; then
        local bad="$SENTINELOPS_LOG_LEVEL"
        SENTINELOPS_LOG_LEVEL=INFO
        log_warn "ignoring invalid SENTINELOPS_LOG_LEVEL=${bad@Q} (valid: DEBUG INFO WARN ERROR); using INFO"
    fi
}

# resolve_config_path
# Prints the configuration file to use, or nothing for built-in defaults.
resolve_config_path() {
    if [[ -n "$OPT_CONFIG" ]]; then
        printf '%s' "$OPT_CONFIG"
    elif [[ -n "${SENTINELOPS_CONFIG:-}" ]]; then
        printf '%s' "$SENTINELOPS_CONFIG"
    elif [[ -e "$SENTINELOPS_HOME/config/sentinelops.conf" ]]; then
        printf '%s' "$SENTINELOPS_HOME/config/sentinelops.conf"
    fi
}

# load_config
# Loads the configuration and logs every warning and error.
# Returns 0 if valid, 1 otherwise.
load_config() {
    local path msg status=0
    path="$(resolve_config_path)"

    if [[ -z "$path" ]]; then
        log_warn "no configuration file found; using built-in defaults" \
                 "(copy config/sentinelops.conf.example to config/sentinelops.conf)"
    else
        log_debug "using configuration file ${path@Q}"
    fi

    config_load "$path" || status=1

    for msg in "${SO_CONFIG_WARNINGS[@]}"; do
        log_warn "config: $msg"
    done
    for msg in "${SO_CONFIG_ERRORS[@]}"; do
        log_error "config: $msg"
    done
    return "$status"
}

# json_string_array ITEMS...
# Prints a JSON array of strings.
json_string_array() {
    local item sep=""
    printf '['
    for item in "$@"; do
        printf '%s"%s"' "$sep" "$(json_escape "$item")"
        sep=","
    done
    printf ']'
}

cmd_version() {
    if (( OPT_JSON )); then
        printf '{"name":"sentinelops","version":"%s"}\n' "$(json_escape "$SO_VERSION")"
    else
        printf 'sentinelops %s\n' "$SO_VERSION"
    fi
    return "$SO_EXIT_OK"
}

cmd_validate_config() {
    local valid=true status="$SO_EXIT_OK"
    if ! load_config; then
        valid=false
        status="$SO_EXIT_USAGE"
    fi

    local source_desc="${SO_CONFIG_FILE:-built-in defaults}"

    if (( OPT_JSON )); then
        local file_json="null"
        [[ -n "$SO_CONFIG_FILE" ]] && file_json="\"$(json_escape "$SO_CONFIG_FILE")\""
        printf '{"valid":%s,"config_file":%s,"errors":%s,"warnings":%s}\n' \
            "$valid" "$file_json" \
            "$(json_string_array "${SO_CONFIG_ERRORS[@]}")" \
            "$(json_string_array "${SO_CONFIG_WARNINGS[@]}")"
    elif [[ "$valid" == true ]]; then
        printf 'Configuration valid: %s (%d warning(s))\n' "$source_desc" "${#SO_CONFIG_WARNINGS[@]}"
    else
        printf 'Configuration invalid: %s (%d error(s))\n' "$source_desc" "${#SO_CONFIG_ERRORS[@]}"
    fi
    return "$status"
}

cmd_deps() {
    local cmd path status="$SO_EXIT_OK"

    printf 'Bash: %s\n\nRequired:\n' "$BASH_VERSION"
    for cmd in "${SO_REQUIRED_CMDS[@]}"; do
        if path="$(command -v -- "$cmd")"; then
            printf '  %-10s %-8s %s\n' "$cmd" "found" "$path"
        else
            printf '  %-10s %-8s\n' "$cmd" "MISSING"
            log_error "required command '$cmd' not found"
            status="$SO_EXIT_FAILURE"
        fi
    done

    printf '\nOptional:\n'
    for cmd in "${SO_OPTIONAL_CMDS[@]}"; do
        local purpose="${SO_OPTIONAL_PURPOSE[$cmd]}"
        if path="$(command -v -- "$cmd")"; then
            printf '  %-10s %-8s %s\n' "$cmd" "found" "$path"
            if [[ "$cmd" == "systemctl" ]] && ! systemd_is_running; then
                printf '  %-10s %-8s %s\n' "" "" "note: systemd is not running; service checks will report UNKNOWN"
                log_warn "systemctl is installed but systemd is not running (common on WSL2)"
            fi
        else
            printf '  %-10s %-8s needed for %s\n' "$cmd" "MISSING" "$purpose"
            log_warn "optional command '$cmd' not found: $purpose will report UNKNOWN"
        fi
    done
    return "$status"
}

cmd_check() {
    load_config || return "$SO_EXIT_USAGE"

    local -a modules=()
    local m
    if [[ -n "$OPT_MODULE" ]]; then
        if ! config_is_true "${SO_MODULE_ENABLE_KEY[$OPT_MODULE]}"; then
            log_info "module '$OPT_MODULE' is disabled in the configuration but was requested explicitly"
        fi
        modules=("$OPT_MODULE")
    else
        for m in "${SO_MODULES[@]}"; do
            config_is_true "${SO_MODULE_ENABLE_KEY[$m]}" && modules+=("$m")
        done
    fi

    if (( ${#modules[@]} == 0 )); then
        log_error "all modules are disabled in the configuration; nothing was checked"
        printf 'Overall status: UNKNOWN\n'
        return "$SO_EXIT_FAILURE"
    fi

    # Phase 1: no collectors exist yet. Report UNKNOWN, never OK: an absent
    # measurement is not evidence of health.
    for m in "${modules[@]}"; do
        printf '[UNKNOWN] %s: module not implemented yet\n' "$m"
    done
    printf 'Overall status: UNKNOWN\n'
    log_warn "no monitoring modules are implemented yet (Phase 2)"
    return "$SO_EXIT_FAILURE"
}

main() {
    parse_args "$@" || return "$SO_EXIT_USAGE"

    if (( OPT_HELP )) || [[ "$OPT_COMMAND" == "help" ]]; then
        usage
        return "$SO_EXIT_OK"
    fi

    if [[ -z "$OPT_COMMAND" ]]; then
        usage >&2
        return "$SO_EXIT_USAGE"
    fi

    setup_logging

    case "$OPT_COMMAND" in
        check|validate-config|deps|version) ;;
        report|incidents)
            usage_error "'$OPT_COMMAND' is planned but not implemented yet"
            return "$SO_EXIT_USAGE"
            ;;
        *)
            usage_error "unknown command '$OPT_COMMAND'"
            return "$SO_EXIT_USAGE"
            ;;
    esac

    check_option_compatibility || return "$SO_EXIT_USAGE"

    case "$OPT_COMMAND" in
        check)           cmd_check ;;
        validate-config) cmd_validate_config ;;
        deps)            cmd_deps ;;
        version)         cmd_version ;;
    esac
}

main "$@"
exit $?
