# PROJECT SYNOPSIS AND IMPLEMENTATION SPECIFICATION
## Linux Production Monitoring & Incident Response Platform

**Project Name:** SentinelOps — Linux Monitoring and Incident Response Toolkit

**Project Type:** Systems Engineering, Linux Administration, Bash Automation, DevOps and Site Reliability Engineering (SRE)

**Primary Technologies:** Linux, Bash, GNU/Linux command-line utilities, Git, ShellCheck, Python (optional later), SQLite (optional later), Docker (advanced phase), GitHub Actions (CI/CD)

**Target Environment:** Ubuntu Linux, including Ubuntu on WSL2, with compatibility for a standard Linux virtual machine or server.

**Development Approach:** Incremental, test-driven, modular, documented and security-conscious.

---

# 1. PROJECT OVERVIEW

## 1.1 Problem Statement

Modern applications depend on Linux servers and infrastructure that must remain available, responsive and secure. Infrastructure failures can occur because of excessive CPU utilization, memory pressure, disk exhaustion, stopped services, failed application processes, network connectivity problems and abnormal log activity.

Manually checking each server using commands such as `top`, `free`, `df`, `ps`, `systemctl`, `journalctl` and `grep` is repetitive and makes it difficult to maintain consistent monitoring and incident records.

Enterprise monitoring systems provide sophisticated observability, but understanding the Linux operating system and the mechanisms underlying these systems is essential for infrastructure engineers, DevOps engineers and Site Reliability Engineers.

SentinelOps will address this problem by providing a modular, Bash-based monitoring toolkit that periodically collects system information, evaluates configurable health thresholds, detects operational incidents, records structured events and generates useful diagnostic reports.

The project will begin as a command-line tool and evolve into a tested, configurable and container-compatible monitoring platform.

## 1.2 Project Objectives

The system must:

1. Monitor CPU utilization, memory utilization and disk capacity.
2. Identify resource usage exceeding configurable warning and critical thresholds.
3. Monitor selected processes and system services.
4. Check the availability of configured network endpoints.
5. Analyze accessible system and application logs for selected error patterns.
6. Generate timestamped, structured monitoring reports.
7. Track incident creation, persistence, recovery and resolution.
8. Support scheduled execution using cron or systemd timers.
9. Handle missing utilities, permission errors, invalid configuration and command failures gracefully.
10. Provide safe, configurable alerting and optional recovery actions.
11. Include automated tests, documentation and a Git-based development workflow.
12. Provide a foundation for future dashboard, Docker, CI/CD and metrics integrations.

## 1.3 Intended Users

- Linux system administrators
- DevOps engineers
- Site Reliability Engineers
- Cloud and infrastructure engineers
- Developers responsible for operating Linux-hosted applications
- Students learning Linux internals, Bash scripting and infrastructure automation

## 1.4 Project Philosophy

The initial implementation must remain Bash-first.

Do not implement the monitoring engine entirely in Python or rely on an external monitoring product to do the project's main work. Bash scripts must collect and evaluate the core metrics themselves using Linux utilities and appropriate kernel interfaces.

Use standard, understandable tools rather than unnecessary frameworks.

The project must prioritize correctness, reliability, observability, maintainability and safe behavior over visual appearance.

---

# 2. SYSTEM ARCHITECTURE

The initial architecture should be modular and command-line driven.

    Linux Host
        |
        v
    Configuration Loader
        |
        v
    Monitoring Scheduler / CLI
        |
        +--> CPU Monitor
        |
        +--> Memory Monitor
        |
        +--> Disk Monitor
        |
        +--> Process Monitor
        |
        +--> Service Monitor
        |
        +--> Network Monitor
        |
        +--> Log Analyzer
        |
        v
    Metric Normalization
        |
        v
    Threshold Evaluation
        |
        v
    Incident Manager
        |
        +--> Incident Event Log
        |
        +--> Current Health Report
        |
        +--> Recovery Events
        |
        +--> Alert Dispatcher
        |
        v
    CLI Summary / JSON Reports / Diagnostic Reports

Each monitoring module must operate independently, return a consistent result and avoid terminating the entire monitoring run when one check fails.

## 2.1 Architectural Components

### A. Configuration Manager

Loads thresholds, monitored services, processes, endpoints, log paths, intervals and enabled modules from a configuration file.

### B. Monitoring Engine

Invokes the enabled monitoring modules, gathers their results and passes them to the threshold evaluator.

### C. Threshold Evaluator

Classifies measurements as `OK`, `WARNING`, `CRITICAL` or `UNKNOWN`.

### D. Incident Manager

Creates and updates incident records, identifies continuing incidents and records recovery when conditions return to normal.

### E. Event Logger

Records structured JSON Lines events with timestamps, event types, severity and supporting details.

### F. Reporting Module

Generates human-readable terminal output and machine-readable reports.

### G. Alert Dispatcher

Initially supports console notifications and optional email integration. Future integrations may include Slack or compatible webhook endpoints.

### H. Scheduler

Allows one-shot execution and repeated execution through cron or a systemd timer.

---

# 3. FUNCTIONAL REQUIREMENTS

## 3.1 CPU Monitoring

Implement a CPU monitoring module.

Requirements:

- Collect CPU utilization using a reliable Linux-compatible method.
- Prefer reading `/proc/stat` twice with a suitable sampling interval or using a suitable system utility.
- Do not depend exclusively on parsing the human-readable output of `top`, which can vary between implementations and locales.
- Calculate utilization correctly and document the calculation.
- Support configurable warning and critical thresholds.
- Report the measured value, thresholds, timestamp and health status.
- Handle missing or unreadable metric sources gracefully.

Example output:

    [OK] CPU utilization: 34.2%
    [WARNING] CPU utilization: 84.6%
    [CRITICAL] CPU utilization: 96.1%

Use illustrative thresholds of 80% for warning and 90% for critical by default. These must be configurable.

Do not confuse a momentary CPU spike with a sustained problem. Add configurable sampling or consecutive-check behavior in a later iteration.

## 3.2 Memory Monitoring

Collect memory metrics from `/proc/meminfo` or a suitable standard utility.

Calculate memory utilization consistently and document which memory fields are used.

Requirements:

- Total memory
- Available memory
- Used memory
- Used-memory percentage
- Warning and critical thresholds
- Graceful handling of unavailable measurements

Prefer `MemAvailable` where supported instead of treating all memory used for caching as unavailable.

Example:

    Memory Total: 7.7 GiB
    Memory Used:  5.1 GiB
    Memory Usage: 66.2%
    Status: OK

Values must be calculated from actual measurements, not hardcoded examples.

## 3.3 Disk Monitoring

Monitor configured mounted filesystems.

Requirements:

- Collect filesystem capacity using `df`.
- Report mount point, total capacity, used capacity, available capacity and percentage used.
- Configure exclusions for pseudo-filesystems and irrelevant mounts.
- Identify warning and critical conditions.
- Detect collection failures and avoid reporting them as healthy results.
- Avoid traversing large directories unnecessarily during normal monitoring.

Example:

    Mount Point: /
    Usage: 83%
    Status: WARNING

Optionally add a diagnostic command that identifies the largest directories under an explicitly configured path. This diagnostic must be separate from the regular monitoring cycle because directory scans can be expensive.

The initial version must never delete files automatically to free disk space.

## 3.4 Process Monitoring

Support configurable process checks.

Requirements:

- Identify whether selected processes are present.
- Support executable names and carefully defined matching rules.
- Avoid unreliable substring matching where possible.
- Report PID and basic process information when available.
- Distinguish a missing process from an inspection error.
- Optionally identify the processes consuming the most CPU or memory.

Example:

    sshd: RUNNING
    nginx: NOT_FOUND
    python-worker: RUNNING

Process presence does not always establish application health. Clearly distinguish process checks from service health checks.

## 3.5 System Service Monitoring

Support configurable systemd service checks.

Use `systemctl` when available and handle its exit codes correctly.

Requirements:

- Check whether a service is active.
- Report inactive, failed, unknown and active states separately.
- Support an explicit list of services to monitor.
- Detect environments without systemd, including some WSL configurations.
- Never assume that all Linux environments use systemd.
- Do not require root privileges merely to inspect services where user permissions allow it.

Example:

    ssh.service: ACTIVE
    nginx.service: FAILED
    docker.service: UNKNOWN

A failed command or unavailable service manager must not automatically be interpreted as proof that the monitored service is healthy or failed.

## 3.6 Network Monitoring

Implement endpoint health checks.

Each configured endpoint should support:

- A descriptive name
- A hostname or IP address
- A port where applicable
- An optional HTTP or HTTPS URL
- A configurable timeout
- An expected HTTP status or acceptable status range where applicable

For HTTP endpoints, use `curl` with a timeout and capture the HTTP response status.

For TCP checks, use an appropriate available utility, with a documented fallback strategy.

Requirements:

- Record success or failure.
- Record response time when measurable.
- Distinguish DNS resolution failures, connection failures, timeouts and unexpected HTTP statuses where feasible.
- Avoid depending on ICMP ping alone because ICMP may be blocked.
- Do not scan arbitrary hosts or ports.
- Only test explicitly configured endpoints that the user is authorized to access.

Example:

    GitHub API: UP
    Local Application: DOWN
    Database Endpoint: TIMEOUT

Network checks should not create excessive requests. Enforce reasonable timeouts and configurable intervals.

## 3.7 Log Analysis

Build a log-analysis module that scans configured, readable log files for selected patterns.

Example patterns:

- `ERROR`
- `CRITICAL`
- `FATAL`
- `Failed password`
- `Connection refused`

Requirements:

- Use standard utilities such as `grep`, `awk` and `sort` where appropriate.
- Support configurable patterns.
- Count matches and provide a limited diagnostic summary.
- Avoid loading entire large logs into memory.
- Handle log rotation, missing files and permission errors.
- Avoid exposing full log contents unnecessarily.
- Do not interpret every occurrence of the word `error` as a confirmed incident without context.
- Allow users to disable patterns that are not relevant to their applications.

Security log analysis must be read-only and limited to systems and logs the user is authorized to inspect.

Do not automatically block IP addresses or modify firewall rules.

## 3.8 Threshold Evaluation

Create a shared mechanism for classifying measurements.

Supported states:

- `OK`
- `WARNING`
- `CRITICAL`
- `UNKNOWN`

Requirements:

- Thresholds must be configurable.
- Critical conditions must take precedence over warning conditions.
- Invalid or unavailable measurements must not be classified as `OK`.
- Missing metrics must not silently be interpreted as zero.
- Different metric types must support appropriate comparison rules.
- Each result must include a timestamp and explanatory message.

Threshold evaluation must be separated from metric collection so that modules can be tested independently.

## 3.9 Incident Management

Implement incident lifecycle tracking.

An incident should contain:

- Unique incident ID
- Incident type
- Resource or component
- Severity
- First detected timestamp
- Last observed timestamp
- Current state
- Relevant measurement
- Threshold that was exceeded
- Diagnostic message
- Recovery timestamp when resolved

Required lifecycle:

    HEALTHY
       |
       v
    PROBLEM DETECTED
       |
       v
    INCIDENT OPENED
       |
       +--> Problem persists: update incident
       |
       v
    CONDITION RECOVERS
       |
       v
    INCIDENT RESOLVED

Requirements:

- Avoid generating a new incident on every monitoring cycle for the same persistent problem.
- Generate a recovery event when an incident returns to normal.
- Support configurable consecutive-failure rules to reduce alert noise.
- Ensure incident IDs are unique.
- Preserve the event history.
- Distinguish the current incident state from historical events.
- Handle process interruption without corrupting stored records.

Implement the initial incident store using structured JSON Lines events and a separate current-state representation if required.

SQLite may be introduced later if reliable querying, historical statistics or concurrent writers justify it.

## 3.10 Alerting

Implement the following alerting stages:

**Stage 1: Console**

Print readable alerts to standard output or standard error as appropriate.

**Stage 2: Persistent records**

Write incidents and recovery events to the event log.

**Stage 3: Optional notifications**

Support a configurable email or webhook integration after the core system is stable.

Requirements:

- Avoid duplicate notifications for an unchanged incident.
- Record notification failures.
- Keep notification credentials out of source code and Git.
- Never print secrets in logs.
- Make notification providers optional.
- Provide a test or dry-run mode.

The core monitoring system must continue functioning when an optional notification provider is unavailable.

## 3.11 Automatic Recovery

Automatic recovery must be an optional advanced feature, disabled by default.

Initially, the tool must only report problems and recommend diagnostic actions.

If recovery actions are implemented later:

- Require explicit per-service configuration.
- Restrict actions to an allowlist.
- Do not execute arbitrary commands from the configuration file.
- Avoid restarting critical services without explicit authorization.
- Include rate limits and retry limits.
- Record the reason for every action.
- Verify whether recovery succeeded.
- Support dry-run mode.
- Never kill arbitrary processes or delete files automatically.

The default installation must be safe to run as a regular user.

## 3.12 Reporting

Provide:

1. A concise terminal summary.
2. A detailed per-module report.
3. JSON output for machine consumption.
4. Historical incident events.
5. A diagnostic report for troubleshooting.

Example terminal report:

    SENTINELOPS SYSTEM HEALTH
    =========================
    Host: ubuntu-dev
    Timestamp: 2026-10-20T12:00:00Z

    CPU:          OK          34.2%
    Memory:       WARNING     83.4%
    Disk:         OK          62.1%
    Processes:    OK
    Services:     WARNING     1 issue
    Network:      OK

    Overall Status: WARNING

    Open Incidents: 1
    New Incidents:  0
    Resolved:       0

The above values are illustrative only.

Define and document the overall health calculation. For example, an overall status may be the highest severity among applicable checks, while a separate count reports checks that are unknown or unavailable.

The report must not show an overall healthy state if a critical monitoring module failed to collect its required metrics.

---

# 4. CONFIGURATION DESIGN

Create a configuration directory containing an example configuration file.

Prefer a readable, validated configuration format. If using Bash alone for the initial implementation, use a simple documented key-value format or a restricted configuration format rather than sourcing an arbitrary file containing executable commands.

A future Python component may support YAML or TOML.

Illustrative configuration:

    APP_NAME="SentinelOps"

    CPU_WARNING=80
    CPU_CRITICAL=90

    MEMORY_WARNING=80
    MEMORY_CRITICAL=90

    DISK_WARNING=80
    DISK_CRITICAL=90

    CHECK_INTERVAL=60

    ENABLE_CPU=true
    ENABLE_MEMORY=true
    ENABLE_DISK=true
    ENABLE_PROCESS=true
    ENABLE_SERVICES=true
    ENABLE_NETWORK=true
    ENABLE_LOG_ANALYSIS=true

    LOG_DIRECTORY="./logs"
    REPORT_DIRECTORY="./reports"

    MONITORED_PROCESSES=(
      "python"
      "sshd"
    )

The final implementation must use one consistent configuration schema, validate every field and document all supported options. The sample above illustrates the intended configuration and is not a requirement to use Bash array syntax in the final format.

Requirements:

- Validate numerical thresholds and their ordering.
- Reject malformed values.
- Validate boolean fields.
- Check configured paths.
- Provide safe defaults.
- Keep environment-specific values out of the core code.
- Supply a sample configuration.
- Document how to add services, processes and endpoints.
- Ensure paths containing spaces are handled correctly.

---

# 5. COMMAND-LINE INTERFACE

Create a single main executable called `sentinelops.sh`.

The interface should support the following commands or equivalent subcommands:

    ./sentinelops.sh --help
    ./sentinelops.sh check
    ./sentinelops.sh check --module cpu
    ./sentinelops.sh check --module memory
    ./sentinelops.sh check --module disk
    ./sentinelops.sh check --module processes
    ./sentinelops.sh check --module services
    ./sentinelops.sh check --module network
    ./sentinelops.sh check --module logs
    ./sentinelops.sh report
    ./sentinelops.sh incidents
    ./sentinelops.sh validate-config
    ./sentinelops.sh version

The implementation may use a slightly different syntax if it is more consistent, but it must document and test every supported command.

Requirements:

- Provide useful help output.
- Validate command-line arguments.
- Support an explicit configuration path.
- Support machine-readable JSON output.
- Use predictable exit codes.
- Send diagnostics to standard error when appropriate.
- Never silently ignore invalid arguments.
- Ensure a single-module check does not unnecessarily run every other module.

Suggested exit-code convention:

- `0`: Successful execution with no warning or critical findings.
- `1`: Execution succeeded, but a warning or critical condition was detected.
- `2`: Invalid arguments or configuration.
- `3`: Monitoring execution failed or essential data could not be collected.

Document how partial failures are represented when a run includes multiple modules.

---

# 6. PROJECT DIRECTORY STRUCTURE

Use the following initial repository structure:

    sentinelops/
    ├── sentinelops.sh
    ├── README.md
    ├── LICENSE
    ├── .gitignore
    ├── .editorconfig
    ├── .shellcheckrc
    ├── Makefile
    │
    ├── config/
    │   ├── sentinelops.conf.example
    │   └── endpoints.conf.example
    │
    ├── scripts/
    │   ├── common.sh
    │   ├── config.sh
    │   ├── cpu.sh
    │   ├── memory.sh
    │   ├── disk.sh
    │   ├── processes.sh
    │   ├── services.sh
    │   ├── network.sh
    │   ├── logs.sh
    │   ├── evaluator.sh
    │   ├── incidents.sh
    │   ├── reporting.sh
    │   └── alerts.sh
    │
    ├── tests/
    │   ├── run_tests.sh
    │   ├── test_config.sh
    │   ├── test_cpu.sh
    │   ├── test_memory.sh
    │   ├── test_disk.sh
    │   ├── test_evaluator.sh
    │   ├── test_incidents.sh
    │   └── fixtures/
    │
    ├── logs/
    │   └── .gitkeep
    │
    ├── reports/
    │   └── .gitkeep
    │
    ├── docs/
    │   ├── ARCHITECTURE.md
    │   ├── INSTALLATION.md
    │   ├── CONFIGURATION.md
    │   ├── TROUBLESHOOTING.md
    │   ├── SECURITY.md
    │   ├── TESTING.md
    │   └── ROADMAP.md
    │
    ├── .github/
    │   └── workflows/
    │       └── shellcheck.yml
    │
    └── LICENSE

This structure is a starting point, not permission to create empty files for every future feature.

Create a module only when it has a defined interface and useful implementation. If a different structure improves modularity or testability, explain the change in the architecture documentation.

Keep the initial core implementation in Bash. Additional languages must be introduced only in later phases.

---

# 7. NON-FUNCTIONAL REQUIREMENTS

## Reliability

- One module failing must not automatically terminate unrelated checks.
- Use explicit error handling.
- Avoid hiding failed commands with unconditional success fallbacks.
- Handle missing dependencies.
- Handle empty command output and unexpected input.
- Prevent duplicate concurrent executions where necessary.
- Use temporary files safely.
- Avoid corrupting persistent incident state during interruption.

## Performance

- Avoid expensive scans during every monitoring cycle.
- Do not repeatedly parse the same large log file unnecessarily.
- Use configurable intervals and timeouts.
- Keep resource overhead low.
- Document the approximate overhead and limitations.

## Security

- Do not require root privileges by default.
- Never execute arbitrary configuration contents as shell code.
- Do not store passwords, API keys or tokens in Git.
- Do not modify firewall rules, kill processes or delete files in the initial version.
- Do not send telemetry or external requests except for explicitly configured health checks and notification providers.
- Validate input before using it in commands.
- Quote shell variables appropriately.
- Avoid `eval`.
- Follow least-privilege principles.
- Never disable operating-system security controls to make the tool work.

## Portability

- Target Bash 4.4 or later where feasible, with compatibility notes for older distributions.
- Document required external utilities.
- Detect optional dependencies at runtime.
- Use portable alternatives where reasonable.
- Clearly document which features require systemd or GNU-specific utilities.
- Handle WSL environments without assuming that system services behave exactly as they do on a full Linux server.

## Maintainability

- Use descriptive function and variable names.
- Keep modules small and focused.
- Document non-obvious calculations.
- Avoid unnecessary global state.
- Centralize common logging and error-handling functions.
- Keep collection, evaluation, incident management and reporting logically separate.

---

# 8. TESTING STRATEGY

Testing is mandatory, not an optional finishing step.

Use Bash-based automated tests and ShellCheck.

## 8.1 Unit Tests

Test:

- Configuration parsing and validation
- Threshold boundary conditions
- CPU calculations
- Memory calculations
- Disk threshold evaluation
- Missing command handling
- Unknown metric handling
- Incident creation
- Duplicate incident suppression
- Incident recovery
- Invalid arguments
- JSON output validity
- Exit-code behavior

## 8.2 Integration Tests

Test:

- Full monitoring execution
- Single-module execution
- Report generation
- Log creation
- Incident persistence
- Configuration overrides
- Multiple simultaneous issues
- Partial monitoring failures

## 8.3 Failure Scenarios

Simulate:

- Disk usage above a threshold
- Missing monitored process
- Unavailable endpoint
- Missing optional dependency
- Unreadable log file
- Invalid configuration
- Malformed metric input
- Interrupted monitoring run
- Unavailable service manager

Tests must not require generating actual dangerous system conditions.

## 8.4 Safe Test Design

- Use fixtures and temporary directories.
- Mock external commands where necessary.
- Do not alter real system services to test service failures.
- Do not fill the actual disk to test disk alerts.
- Do not depend on external network connectivity for every unit test.
- Keep tests repeatable.
- Ensure tests clean up their temporary files.
- Do not run destructive commands on the host.

The test suite should work in a normal Ubuntu development environment with documented dependencies.

## 8.5 Static Analysis

Use ShellCheck on all project shell scripts.

Provide commands such as:

    shellcheck sentinelops.sh scripts/*.sh tests/*.sh

Configure the project so that avoidable ShellCheck warnings are corrected rather than globally suppressed.

If a warning must be suppressed, add a narrow suppression with an explanation.

---

# 9. DEVELOPMENT PHASES

Implement the project incrementally. Do not attempt to build every advanced feature in one pass.

## Phase 1: Foundation

Deliver:

- Repository structure
- Main CLI
- Configuration loader
- Shared logging and error-handling functions
- Help and version commands
- Dependency checks
- Configuration validation
- Initial tests
- README and installation instructions

Acceptance criteria:

- The tool starts correctly.
- Invalid configuration is rejected.
- Help output is useful.
- Missing optional dependencies are handled cleanly.
- No monitoring checks are falsely reported as healthy.

## Phase 2: Core Monitoring

Implement:

- CPU monitoring
- Memory monitoring
- Disk monitoring
- Process monitoring
- Service monitoring
- Network monitoring
- Log analysis

Acceptance criteria:

- Each module can run independently.
- Every module returns a consistent result.
- Thresholds are configurable.
- Failed collection is distinguishable from a healthy measurement.
- Test fixtures cover normal and abnormal cases.

## Phase 3: Incident Management

Implement:

- Severity classification
- Incident IDs
- Structured event logging
- Persistent incident state
- Duplicate suppression
- Recovery detection
- Historical reporting

Acceptance criteria:

- Persistent problems do not create unlimited duplicate incidents.
- Recovery is recorded.
- State survives normal process termination and restart.
- Invalid or incomplete records do not silently corrupt incident history.

## Phase 4: Scheduling and Notifications

Implement:

- Repeated execution support
- Cron or systemd timer instructions
- Configurable notification providers
- Notification deduplication
- Notification failure handling

Acceptance criteria:

- Scheduled runs produce usable reports.
- No notification provider is mandatory.
- The core system continues operating when notifications fail.
- Scheduling does not produce uncontrolled overlapping runs.

## Phase 5: Advanced Bash Engineering

Improve:

- Strict but appropriate error handling
- Dependency detection
- Locking and concurrency control
- Timeout handling
- Rotation or retention of generated logs
- Diagnostic reports
- Test coverage
- Documentation

Do not enable destructive automatic recovery actions.

## Phase 6: Docker and CI/CD

Only after the Bash implementation is stable:

- Add a Dockerfile.
- Run the monitoring application in a suitable container environment.
- Document container permission and visibility limitations.
- Add GitHub Actions to run ShellCheck and tests.
- Build and test the container image.
- Add a documented release workflow.

A containerized monitor may not see the host's complete metrics by default. Document which metrics describe the container and which describe the host. Do not use privileged container access as a default workaround.

## Phase 7: Observability Extension

Introduce an optional metrics integration.

Potential extensions:

- Prometheus-compatible metrics export
- Grafana dashboards
- Historical trends
- Incident frequency summaries
- Resource usage reports

Clearly distinguish SentinelOps's own monitoring functionality from any functionality provided by Prometheus or Grafana.

## Phase 8: Optional Dashboard

Only after the core tool and monitoring data are stable, consider:

- Python Flask API
- SQLite incident history
- HTML/CSS/JavaScript dashboard
- Resource usage charts
- Incident filtering
- Service health summaries

The dashboard must consume the core monitoring data rather than replace the Bash monitoring engine.

---

# 10. DOCUMENTATION REQUIREMENTS

The repository must include a complete README with:

1. Project overview
2. Problem statement
3. Features
4. Architecture diagram
5. Technology stack
6. Prerequisites
7. Installation steps
8. Configuration instructions
9. Example commands
10. Example reports
11. Testing instructions
12. Security considerations
13. Known limitations
14. Troubleshooting
15. Development roadmap
16. Future enhancements
17. Acknowledgements for external references, if used

Provide a separate installation guide for Ubuntu and WSL2.

Include a clear explanation of how each monitoring module works and which Linux commands or kernel interfaces it uses.

Document every command-line option and exit code.

Do not claim features are implemented unless they actually work.

---

# 11. EXPECTED DELIVERABLES

At the end of the initial implementation, deliver:

- A functioning Bash monitoring application
- Modular monitoring scripts
- Validated configuration
- Structured incident and event logging
- Terminal and JSON reporting
- Automated tests
- ShellCheck-clean code, except for documented justified suppressions
- GitHub Actions workflow for testing
- Sample configuration files
- Installation instructions
- Architecture documentation
- Security documentation
- Troubleshooting guide
- A roadmap for Docker, CI/CD, metrics and dashboard extensions

Provide a final implementation summary identifying:

- Features implemented
- Features partially implemented
- Features not implemented
- Commands executed during testing
- Test results
- Known bugs and limitations
- Manual setup still required
- Exact commands needed to run the project

Do not claim that tests pass unless they were actually executed and passed.

---

# 12. INSTRUCTIONS TO THE CLI AGENT

Act as a senior Linux systems engineer, Bash developer, DevOps engineer and code reviewer.

Your task is to implement SentinelOps in the current working repository.

Follow these rules:

1. Inspect the current working directory before creating or modifying files.
2. If a project already exists, inspect it and preserve unrelated user work.
3. Create a short implementation plan before making substantial changes.
4. Implement Phase 1 first, then validate it before moving to Phase 2.
5. Do not generate a huge collection of unimplemented placeholder files.
6. Use Bash for the core monitoring engine.
7. Write modular, readable code with clear function boundaries.
8. Use ShellCheck and automated tests throughout development.
9. Use fixtures and mocked commands to test failures safely.
10. Never run destructive commands on the host.
11. Never delete existing user data.
12. Do not change system configuration or install packages without permission.
13. If a required dependency is missing, explain how to install it and request approval when installation requires authorization.
14. Do not require root privileges by default.
15. Do not introduce a database, web server, Docker or Kubernetes into the initial MVP unless required for a clearly justified reason.
16. Do not hardcode machine metrics, timestamps, hostnames or successful test results.
17. Do not silently ignore errors.
18. Keep secrets and machine-specific configuration out of Git.
19. Run tests and static analysis after meaningful changes.
20. Fix failures before declaring a phase complete.
21. Keep documentation synchronized with the implementation.
22. Explain significant architectural decisions in concise notes.
23. At each phase boundary, summarize changes, tests and remaining work.
24. Stop and report any unresolved failure rather than falsely claiming completion.

## Definition of Done for the Initial MVP

The first complete MVP must be able to:

- Start using a documented command.
- Validate its configuration.
- Collect CPU, memory and disk metrics.
- Check selected processes.
- Check configured services when supported.
- Test configured network endpoints.
- Analyze configured logs.
- Classify measurements into the documented health states.
- Produce a terminal summary.
- Generate valid JSON output.
- Record incident and recovery events.
- Avoid repeatedly opening the same incident during an ongoing problem.
- Handle missing dependencies and partial failures.
- Run automated tests.
- Pass ShellCheck.
- Run without requiring root privileges for ordinary monitoring.
- Provide a complete README and setup instructions.

Start with repository inspection and Phase 1. Do not jump straight to Docker, Kubernetes or a graphical dashboard.

At completion, provide the exact commands for installation, testing and execution, along with a clear explanation of the implemented architecture and any outstanding limitations.
