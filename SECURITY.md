# Security Policy

Gust installs a helper that runs as root, so security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's [private vulnerability reporting](https://github.com/thecmdrunner/gust/security/advisories/new) instead. You'll get a response within a few days.

## Threat model

- `GustHelper` runs as root and listens on `/var/run/gust.sock` (mode `0666`), so **any local user can change fan mode**. It accepts only a fixed set of commands; RPM is clamped to each fan's hardware min/max, and nothing else is exposed. Fan control is considered non-sensitive.
- The helper is installed via an admin-authorized shell script to `/Library/PrivilegedHelperTools/` and `/Library/LaunchDaemons/`, owned by `root:wheel`.
- Anything that lets a caller do more than set fan speed (code execution, file writes, reading other SMC keys, etc.) is a vulnerability — please report it.

## Supported versions

Only the latest release gets fixes.
