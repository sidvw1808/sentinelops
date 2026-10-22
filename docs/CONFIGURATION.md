# Configuration reference

SentinelOps reads a plain-text `KEY=value` file. The file is **parsed, not
executed**: it is never `source`d or `eval`ed, so `$(...)`, backticks and
`$VAR` are treated as literal text and then fail validation.

Run `./sentinelops.sh validate-config` after every change. All problems are
reported at once, with file and line numbers.

## Syntax

```ini
# A comment (only at the start of a line, after optional whitespace)
CPU_WARNING=80
CPU_CRITICAL = 90               # <- NOT a comment: this value is invalid
LOG_DIRECTORY="/var/tmp/my logs"
MONITORED_PROCESSES=sshd,cron
```

- One `KEY=value` per line. Whitespace around the key, `=` and value is ignored.
- Keys are case-sensitive and must be one of the keys listed below. Unknown
  keys (usually typos) are errors.
- A key may appear only once.
- Values may be wrapped in one pair of `"` or `'`, which are removed. There
  are no escape sequences. Unbalanced quotes are errors.
- **No inline comments.** Everything after `=` is the value.
- Windows (CRLF) line endings are accepted.
- Keys you leave out use the default.

## Value types

| Type | Accepted values |
|---|---|
| percent | Integer 0–100, no leading zeros, no decimals |
| seconds | Integer 1–86400 |
| bool | `true` or `false` (lowercase only) |
| path | Non-empty directory path. Relative paths are resolved against the SentinelOps directory, **not** the current directory. Spaces are allowed. Must be a writable directory if it exists; a missing directory produces a warning. |
| list | Comma-separated items, spaces around commas ignored, may be empty. Each item: starts with a letter or digit, then letters, digits, `.` `_` `@` `:` `+` `-`, up to 128 characters. No empty items (`a,,b` or `a,`). |

## Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `CPU_WARNING` | percent | 80 | CPU utilisation warning threshold |
| `CPU_CRITICAL` | percent | 90 | CPU utilisation critical threshold |
| `MEMORY_WARNING` | percent | 80 | Memory utilisation warning threshold |
| `MEMORY_CRITICAL` | percent | 90 | Memory utilisation critical threshold |
| `DISK_WARNING` | percent | 80 | Filesystem usage warning threshold |
| `DISK_CRITICAL` | percent | 90 | Filesystem usage critical threshold |
| `CHECK_INTERVAL` | seconds | 60 | Interval for repeated runs |
| `ENABLE_CPU` | bool | true | Run the CPU module |
| `ENABLE_MEMORY` | bool | true | Run the memory module |
| `ENABLE_DISK` | bool | true | Run the disk module |
| `ENABLE_PROCESS` | bool | true | Run the process module |
| `ENABLE_SERVICES` | bool | true | Run the service module |
| `ENABLE_NETWORK` | bool | true | Run the network module |
| `ENABLE_LOG_ANALYSIS` | bool | true | Run the log analysis module |
| `LOG_DIRECTORY` | path | `./logs` | Where SentinelOps writes its event logs |
| `REPORT_DIRECTORY` | path | `./reports` | Where reports are written |
| `MONITORED_PROCESSES` | list | (empty) | Process names to check (as in `ps -o comm=`) |
| `MONITORED_SERVICES` | list | (empty) | systemd units to check, e.g. `ssh.service` |

### Cross-field rules

- For CPU, MEMORY and DISK: `*_WARNING` must be strictly lower than
  `*_CRITICAL`.

### Module selection

`check` runs every module whose `ENABLE_*` key is `true`. If all are `false`,
`check` exits 3: nothing was checked, so health is unknown.
`check --module NAME` runs that module even if it is disabled (an info message
says so).

## Adding processes and services

```ini
MONITORED_PROCESSES=sshd,cron,nginx
MONITORED_SERVICES=ssh.service,cron.service,nginx.service
```

Find the right names with `ps -eo comm= | sort -u` and
`systemctl list-units --type=service`.

Network endpoints and log patterns will be configured in a separate file
(`config/endpoints.conf`) in Phase 2.
