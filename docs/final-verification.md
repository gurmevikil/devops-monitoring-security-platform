# Final project verification checklist

This checklist records what has been verified in the local Docker Desktop
environment and what still needs a follow-up. A target marked UP means
Prometheus successfully scraped it at the time of the check; it does not
guarantee that every metric is available on every Docker runtime.

## Application and monitoring

- [x] Flask image builds and the `/health` endpoint returns healthy.
- [x] App metrics are exposed at `/metrics` and scraped by Prometheus.
- [x] Docker Compose services start and report healthy/running.
- [x] Prometheus scrape targets for Flask, Node Exporter, cAdvisor, and
  Prometheus were verified UP.
- [x] Linux VM metrics are present from Node Exporter. These are Docker
  Desktop's Linux VM metrics, not Windows host counters.
- [x] cAdvisor exports container CPU and memory metrics. Per-container
  network counters were not available on this Docker Desktop/containerd
  configuration; `docker stats` is the local alternative.
- [x] Grafana health and Prometheus datasource connectivity were verified.
- [x] Application, Linux system, and container dashboard provisioning was
  verified in Grafana.
- [x] Prometheus rule configuration validated; application-down,
  high-error-rate, and container-down alerts were deliberately triggered and
  verified firing, then cleared after recovery.
- [x] `scripts/health-check.sh` passed all configured endpoint and target
  checks against the running stack.
- [ ] Configure and test Alertmanager if email/chat/pager notification
  delivery is required. This project currently only shows local Prometheus
  alert states.

## Security and repository

- [x] Trivy Dockerfile configuration check completed using embedded checks:
  20 checks passed, 0 high/critical failures.
- [ ] Complete Trivy image vulnerability and Python dependency scans. The
  configured database registries refused connections; treat those scans as
  incomplete, not clean. See [security scanning](security-scanning.md).
- [x] `.env`, Trivy cache, and generated scan reports are ignored by Git;
  `.env.example` contains only a placeholder.
- [x] Separate Git commits exist for the implementation phases, including
  automation and GitHub preparation. The latest local commit includes this
  documentation update once committed.
- [ ] Capture genuine Grafana and Prometheus screenshots in `screenshots/`.
- [ ] Publish to GitHub when ready. Publishing was deferred; see the commands
  in the [README](../README.md#github-publishing-when-ready).
- [ ] AWS deployment is an optional future extension and has not been done.

## Useful final commands

From Git Bash at the project root:

```bash
bash scripts/status.sh
bash scripts/health-check.sh
bash scripts/security-scan.sh
git status --short
```

The security scan is complete only if it obtains the vulnerability database,
produces image and dependency reports, and exits `0` with no unexcepted
HIGH/CRITICAL findings. A network/database failure is a failed verification.
