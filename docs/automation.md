# Phase 11: Local automation scripts

Run these commands from **Git Bash** at the project root. The scripts also
change to the repository root themselves, so they can be called from another
working directory by passing their full path. Start Docker Desktop first.

## Start the stack

```bash
bash scripts/start.sh
```

This validates the Compose configuration, builds the Flask image, and starts
all services in the background. It requires `.env`, which contains the local
Grafana password. Create it from `.env.example` if needed, then edit it in
VS Code; never commit `.env`.

Expected result: Compose reports the services started. Confirm with
`bash scripts/status.sh`, then run `bash scripts/health-check.sh` after the
containers have initialized. First-time image and Python package downloads
need registry access.

## Check service status

```bash
bash scripts/status.sh
```

This runs `docker compose ps`. Look for `Up`/`running`; the Flask container
should become `healthy`. A container can be running while its app is not
ready, so use the health-check command as well.

## Check endpoint and target health

```bash
bash scripts/health-check.sh
```

The script checks Flask `/health` and `/metrics`, Prometheus readiness, Node
Exporter metrics, cAdvisor metrics, and Grafana's health endpoint. It then
reads Prometheus's targets API and requires the Flask, Node Exporter, and
cAdvisor jobs to be UP. It exits `0` when every check passes and `1` if any
check fails. The checks use `curl` and Python 3 from Git Bash. For a custom
local port mapping, override a URL, for example:

```bash
APP_URL=http://localhost:5001 bash scripts/health-check.sh
```

Use `docs/troubleshooting.md` for investigation when a check fails.

## Stop the stack

```bash
bash scripts/stop.sh
```

This runs `docker compose down`: containers and the project network are
removed, while named Prometheus and Grafana data volumes remain. It does not
delete images, reports, or volumes.

## Run Trivy and generate reports

```bash
bash scripts/security-scan.sh
```

This is the authoritative scan command. It scans the local image, Python
dependencies, and Dockerfile, and writes JSON and table reports under
`reports/`. It exits nonzero if the HIGH/CRITICAL gate is exceeded or a scan
cannot complete. See `docs/security-scanning.md` for database access and
result interpretation.

The named report command is a convenience wrapper around that same scan:

```bash
bash scripts/generate-security-reports.sh
```

It does not convert old JSON files or claim that stale reports represent the
current image; it reruns the scanner and produces fresh reports. Both commands
accept an optional local image tag as their first argument.

## Executable bit on Windows

Git Bash can run a script as `bash scripts/name.sh` without changing file
permissions. The repository also records executable bits for Linux/macOS
clones. If you want direct invocation in Git Bash, set them once:

```bash
chmod +x scripts/*.sh
./scripts/start.sh
```

PowerShell does not execute Bash scripts natively; open the repository in Git
Bash or prefix each invocation with `bash`.
