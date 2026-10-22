# SentinelOps

Bash-based Linux monitoring and incident response toolkit.
Full specification: @docs/SPEC.md

## Status
- Starting Phase 1 (foundation). Nothing is built yet.

## How I want to work (I am a student; this is my resume project)
- I write ALL the code myself. Do NOT create or edit project files unless I
  explicitly ask for one specific change.
- When I'm stuck: hints and concepts first, not full solutions.
- Review what I write: point out bugs, ShellCheck issues and design problems,
  and explain WHY each matters.
- Teach as we go: name the Linux concepts, point to man pages.
- Ask before big design decisions. Small steps; wait for me between phases.

## Rules for the code
- Bash only for the core. Never `source` or `eval` config. Quote all variables.
- A failed or missing measurement is UNKNOWN, never OK.
- No root, no deleting files, no installing packages without asking me.
- Environment: Ubuntu on WSL2 (systemd may be off).
