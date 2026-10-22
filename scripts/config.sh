#!/usr/bin/env bash
# config.sh - load and validate the SentinelOps configuration file.
#
# The configuration file is DATA, never code. It is read line by line as text
# and is never passed to `source`, `.` or `eval`. A line such as
#     CPU_WARNING=$(rm -rf ~)
# is just a string that fails numeric validation; nothing is executed.
#
# Format (see docs/CONFIGURATION.md):
#     # comment
#     KEY=value
#     KEY="value with spaces"
#     LIST_KEY=item1,item2
#
# Requires common.sh to be sourced first.

if [[ -n "${_SO_CONFIG_LOADED:-}" ]]; then
    return 0
fi
_SO_CONFIG_LOADED=1

# ---------------------------------------------------------------------------
# Schema: every supported key, its type and its default.
#
# Types:
#   percent  integer 0-100
#   seconds  integer 1-86400
#   bool     exactly "true" or "false"
#   path     directory; relative paths are resolved against the project root
#   list     comma-separated names, may be empty
# ---------------------------------------------------------------------------

# Keys in documentation order (associative arrays have no defined order).
declare -gra _SO_SCHEMA_KEYS=(
    CPU_WARNING CPU_CRITICAL
    MEMORY_WARNING MEMORY_CRITICAL
    DISK_WARNING DISK_CRITICAL
    CHECK_INTERVAL
    ENABLE_CPU ENABLE_MEMORY ENABLE_DISK ENABLE_PROCESS
    ENABLE_SERVICES ENABLE_NETWORK ENABLE_LOG_ANALYSIS
    LOG_DIRECTORY REPORT_DIRECTORY
    MONITORED_PROCESSES MONITORED_SERVICES
)

declare -grA _SO_SCHEMA_TYPE=(
    [CPU_WARNING]=percent       [CPU_CRITICAL]=percent
    [MEMORY_WARNING]=percent    [MEMORY_CRITICAL]=percent
    [DISK_WARNING]=percent      [DISK_CRITICAL]=percent
    [CHECK_INTERVAL]=seconds
    [ENABLE_CPU]=bool           [ENABLE_MEMORY]=bool
    [ENABLE_DISK]=bool          [ENABLE_PROCESS]=bool
    [ENABLE_SERVICES]=bool      [ENABLE_NETWORK]=bool
    [ENABLE_LOG_ANALYSIS]=bool
    [LOG_DIRECTORY]=path        [REPORT_DIRECTORY]=path
    [MONITORED_PROCESSES]=list  [MONITORED_SERVICES]=list
)

declare -grA _SO_SCHEMA_DEFAULT=(
    [CPU_WARNING]=80            [CPU_CRITICAL]=90
    [MEMORY_WARNING]=80         [MEMORY_CRITICAL]=90
    [DISK_WARNING]=80           [DISK_CRITICAL]=90
    [CHECK_INTERVAL]=60
    [ENABLE_CPU]=true           [ENABLE_MEMORY]=true
    [ENABLE_DISK]=true          [ENABLE_PROCESS]=true
    [ENABLE_SERVICES]=true      [ENABLE_NETWORK]=true
    [ENABLE_LOG_ANALYSIS]=true
    [LOG_DIRECTORY]=./logs      [REPORT_DIRECTORY]=./reports
    [MONITORED_PROCESSES]=""    [MONITORED_SERVICES]=""
)

# Metrics whose <METRIC>_WARNING must be strictly lower than <METRIC>_CRITICAL.
declare -gra _SO_THRESHOLD_METRICS=(CPU MEMORY DISK)

# A list item must start with a letter or digit (so it can never be mistaken
# for a command-line option like "-9") and may then contain . _ @ : + -
readonly _SO_LIST_ITEM_RE='^[A-Za-z0-9][A-Za-z0-9._@:+-]{0,127}$'

# ---------------------------------------------------------------------------
# Results of the most recent config_load call.
# ---------------------------------------------------------------------------
declare -gA SO_CONFIG=()          # KEY -> validated (normalised) value
declare -gA _SO_CONFIG_ORIGIN=()  # KEY -> "file:line" or "default"
declare -ga SO_CONFIG_ERRORS=()
declare -ga SO_CONFIG_WARNINGS=()
SO_CONFIG_FILE=""                 # file that was loaded; empty = defaults only

_config_error() { SO_CONFIG_ERRORS+=("$1"); }
_config_warn()  { SO_CONFIG_WARNINGS+=("$1"); }

# _config_trim STRING
# Prints STRING without leading/trailing whitespace. [[:space:]] includes the
# carriage return, so this also cleans up Windows (CRLF) line endings.
_config_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"   # remove leading whitespace
    s="${s%"${s##*[![:space:]]}"}"   # remove trailing whitespace
    printf '%s' "$s"
}

# _config_parse_file FILE
# Reads KEY=value lines from FILE into SO_CONFIG. Collects every problem into
# SO_CONFIG_ERRORS instead of stopping at the first one.
_config_parse_file() {
    local file="$1"
    local line key value lineno=0
    local -A seen=()

    # `|| [[ -n "$line" ]]` also processes a last line with no trailing newline.
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        line="$(_config_trim "$line")"

        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            _config_error "$file:$lineno: malformed line (expected KEY=value): ${line@Q}"
            continue
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        if [[ -z "${_SO_SCHEMA_TYPE[$key]:-}" ]]; then
            _config_error "$file:$lineno: unknown key '$key'"
            continue
        fi
        if [[ -n "${seen[$key]:-}" ]]; then
            _config_error "$file:$lineno: duplicate key '$key' (first set on line ${seen[$key]})"
            continue
        fi
        seen[$key]="$lineno"

        # Remove one pair of matching surrounding quotes. No escape sequences
        # or variable expansion are processed: what you write is what you get.
        if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ "$value" == [\"\']* || "$value" == *[\"\'] ]]; then
            _config_error "$file:$lineno: unbalanced quotes in value of '$key'"
            continue
        fi

        SO_CONFIG[$key]="$value"
        _SO_CONFIG_ORIGIN[$key]="$file:$lineno"
    done < "$file"
}

# _config_resolve_path PATH
# Prints PATH as an absolute path. Relative paths are taken relative to the
# project root, not the current directory, so cron and manual runs agree.
_config_resolve_path() {
    local path="$1" root="$2"
    if [[ "$path" == /* ]]; then
        printf '%s' "$path"
    else
        printf '%s/%s' "$root" "${path#./}"
    fi
}

# _config_validate_key KEY ROOT
# Validates SO_CONFIG[KEY] against its schema type and normalises it.
# Returns 0 if valid, 1 otherwise (and records an error).
_config_validate_key() {
    local key="$1" root="$2"
    local type="${_SO_SCHEMA_TYPE[$key]}"
    local value="${SO_CONFIG[$key]}"
    local where="${_SO_CONFIG_ORIGIN[$key]:-default}"

    case "$type" in
        percent)
            # The regex rejects leading zeros: Bash arithmetic would read
            # "08" as an invalid octal number. It also caps the length, so a
            # huge number cannot overflow before the range check.
            if [[ ! "$value" =~ ^(0|[1-9][0-9]{0,2})$ ]] || (( value > 100 )); then
                _config_error "$where: $key must be an integer from 0 to 100, got ${value@Q}"
                return 1
            fi
            ;;
        seconds)
            if [[ ! "$value" =~ ^[1-9][0-9]{0,4}$ ]] || (( value > 86400 )); then
                _config_error "$where: $key must be an integer from 1 to 86400 (seconds), got ${value@Q}"
                return 1
            fi
            ;;
        bool)
            if [[ "$value" != "true" && "$value" != "false" ]]; then
                _config_error "$where: $key must be 'true' or 'false', got ${value@Q}"
                return 1
            fi
            ;;
        path)
            if [[ -z "$value" ]]; then
                _config_error "$where: $key must not be empty"
                return 1
            fi
            local resolved
            resolved="$(_config_resolve_path "$value" "$root")"
            if [[ -e "$resolved" && ! -d "$resolved" ]]; then
                _config_error "$where: $key ${resolved@Q} exists but is not a directory"
                return 1
            elif [[ -d "$resolved" && ! -w "$resolved" ]]; then
                _config_error "$where: $key ${resolved@Q} is not writable by the current user"
                return 1
            elif [[ ! -e "$resolved" ]]; then
                _config_warn "$where: $key ${resolved@Q} does not exist yet"
            fi
            SO_CONFIG[$key]="$resolved"
            ;;
        list)
            local trimmed item
            local -a raw_items=() items=()
            trimmed="$(_config_trim "$value")"
            if [[ -z "$trimmed" ]]; then
                SO_CONFIG[$key]=""
                return 0
            fi
            # `read -a` silently drops a trailing empty field ("a,b,"), so
            # check for that case explicitly.
            if [[ "$trimmed" == *, ]]; then
                _config_error "$where: $key has an empty item (trailing comma)"
                return 1
            fi
            IFS=',' read -r -a raw_items <<< "$trimmed"
            for item in "${raw_items[@]}"; do
                item="$(_config_trim "$item")"
                if [[ -z "$item" ]]; then
                    _config_error "$where: $key has an empty item (check for ',,')"
                    return 1
                fi
                if [[ ! "$item" =~ $_SO_LIST_ITEM_RE ]]; then
                    _config_error "$where: $key item ${item@Q} contains invalid characters (allowed: letters, digits, . _ @ : + -; must start with a letter or digit)"
                    return 1
                fi
                items+=("$item")
            done
            # Store normalised: no spaces around commas.
            local IFS=','
            SO_CONFIG[$key]="${items[*]}"
            ;;
        *)
            # Programming error in the schema, not a user error.
            _config_error "internal error: key '$key' has unknown type '$type'"
            return 1
            ;;
    esac
    return 0
}

# _config_validate_all ROOT
# Validates every key, then the relationships between keys.
_config_validate_all() {
    local root="$1" key metric
    local -A ok=()

    for key in "${_SO_SCHEMA_KEYS[@]}"; do
        if _config_validate_key "$key" "$root"; then
            ok[$key]=1
        fi
    done

    # Only compare thresholds that are individually valid, otherwise we would
    # report a confusing second error for the same bad value.
    for metric in "${_SO_THRESHOLD_METRICS[@]}"; do
        local warn_key="${metric}_WARNING" crit_key="${metric}_CRITICAL"
        if [[ -n "${ok[$warn_key]:-}" && -n "${ok[$crit_key]:-}" ]] &&
           (( SO_CONFIG[$warn_key] >= SO_CONFIG[$crit_key] )); then
            _config_error "$warn_key (${SO_CONFIG[$warn_key]}) must be lower than $crit_key (${SO_CONFIG[$crit_key]})"
        fi
    done
}

# config_load [FILE]
# Loads built-in defaults, overlays FILE if given, and validates the result.
# Afterwards SO_CONFIG holds the values, SO_CONFIG_ERRORS / SO_CONFIG_WARNINGS
# hold any problems. Returns 0 if the configuration is valid, 1 otherwise.
# This function only collects problems; the caller decides how to show them.
config_load() {
    local file="${1:-}"
    local root="${SENTINELOPS_HOME:-}"
    local key

    if [[ -z "$root" ]]; then
        root="$(cd -P -- "${BASH_SOURCE[0]%/*}/.." && pwd)"
    fi

    SO_CONFIG=()
    _SO_CONFIG_ORIGIN=()
    SO_CONFIG_ERRORS=()
    SO_CONFIG_WARNINGS=()
    SO_CONFIG_FILE="$file"

    for key in "${_SO_SCHEMA_KEYS[@]}"; do
        SO_CONFIG[$key]="${_SO_SCHEMA_DEFAULT[$key]}"
    done

    if [[ -n "$file" ]]; then
        # Check the file type before reading: reading a FIFO or a device such
        # as /dev/zero could block forever or never end.
        if [[ ! -e "$file" ]]; then
            _config_error "configuration file ${file@Q} does not exist"
        elif [[ -d "$file" ]]; then
            _config_error "configuration file ${file@Q} is a directory"
        elif [[ ! -f "$file" ]]; then
            _config_error "configuration file ${file@Q} is not a regular file"
        elif [[ ! -r "$file" ]]; then
            _config_error "configuration file ${file@Q} is not readable (check permissions)"
        fi
        if (( ${#SO_CONFIG_ERRORS[@]} > 0 )); then
            return 1
        fi
        _config_parse_file "$file"
    fi

    # Validate even after parse errors, so the user sees every problem at once.
    _config_validate_all "$root"

    (( ${#SO_CONFIG_ERRORS[@]} == 0 ))
}

# config_get KEY
# Prints the value of KEY. Returns 1 for an unknown key.
config_get() {
    local key="${1:-}"
    [[ -n "${_SO_SCHEMA_TYPE[$key]:-}" ]] || return 1
    printf '%s' "${SO_CONFIG[$key]-}"
}

# config_is_true KEY
# Returns 0 if the boolean KEY is "true".
config_is_true() {
    [[ "${SO_CONFIG[${1:-}]-}" == "true" ]]
}

# config_get_list KEY
# Prints each item of list KEY on its own line (nothing for an empty list).
# Usage:  mapfile -t processes < <(config_get_list MONITORED_PROCESSES)
config_get_list() {
    local key="${1:-}" value
    [[ "${_SO_SCHEMA_TYPE[$key]:-}" == "list" ]] || return 1
    value="${SO_CONFIG[$key]-}"
    [[ -n "$value" ]] || return 0
    printf '%s\n' "${value//,/$'\n'}"
}
