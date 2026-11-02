# Phase 10: Production-like troubleshooting scenarios

Use this runbook from the project root. The commands below assume Windows 11
with Docker Desktop and PowerShell unless a heading says Git Bash. The Linux
commands run inside the Flask container or query Linux metrics exposed by Node
Exporter. Docker Desktop runs that Linux host inside its VM; these metrics do
not represent Windows host performance. Prometheus alerts are local UI states;
this project has no Alertmanager notification receiver configured.

## Before investigating

In PowerShell, capture the current state before restarting anything:

```powershell
docker compose ps
docker compose logs --since 10m --tail 100
```

Check Prometheus targets at <http://localhost:9090/targets>, alerts at
<http://localhost:9090/alerts>, and Grafana at <http://localhost:3000>.
Record timestamps and the affected service so logs and metrics can be compared.

## Scenario 1: Flask application is unavailable

**Impact:** users cannot load the app or its API; Prometheus may show
`ApplicationDown` and the `flask-app` target as DOWN.

**Likely causes:** the container exited, the app failed during startup, port
5000 is occupied, or a build/configuration change broke the image.

**Investigate in PowerShell:**

```powershell
docker compose ps app
docker compose logs --since 10m --tail 100 app
$appId = docker compose ps -q app
if ($appId) { docker inspect $appId --format '{{json .State}}' }
Test-NetConnection localhost -Port 5000
Invoke-RestMethod http://localhost:5000/health
```

If `$appId` is empty, Compose has no app container; check whether it was
created and inspect the Compose logs for the build/start failure.

**Procedure and fix:** If the container is exited, read the first startup
exception in its logs. Correct the code or environment setting, then rebuild
and start the service:

```powershell
docker compose up --build -d app
docker compose ps app
```

If logs show a host port conflict, identify the process with
`Get-NetTCPConnection -LocalPort 5000 -State Listen` and either stop the
conflicting development service or change the host side of `ports` in
`docker-compose.yml` (for example `5001:5000`). If the container is healthy
but the Windows request fails, confirm Docker Desktop is running and the port
mapping appears in `docker compose port app 5000`.

**Verify recovery:** `docker compose ps app` reports `healthy`; the request to
`/health` returns `status: healthy`; `flask-app` is UP at
<http://localhost:9090/targets>; `ApplicationDown` returns to Inactive after
Prometheus observes recovery.

**Safe exercise and observed result (2026-11-02):** In PowerShell, run
`docker compose stop app`, then `curl.exe -sS --max-time 3
http://localhost:5000/health`. The request fails while the service is stopped.
After one scrape, Prometheus reports `flask-app` DOWN. Keep it stopped longer
than the rule's 30-second pending period and `ApplicationDown` fires. Restore
it with `docker compose up -d app`; after the next successful scrape, the
health check passes, `flask-app` returns UP, and the alert clears. The outage
was intentionally induced by stopping the container, so the expected recovery
was to start it again; no code or configuration change was needed.

## Scenario 2: Prometheus target is DOWN

**Impact:** metrics and alerts for that scrape job become missing or stale.

**Likely causes:** target container is stopped, the configured service DNS or
port is wrong, the endpoint is unhealthy, or Prometheus cannot parse its
configuration.

**Investigate:** identify the failing job and its **Last error** at
<http://localhost:9090/targets>. In PowerShell:

```powershell
docker compose ps
docker compose logs --since 10m --tail 100 prometheus
docker compose logs --since 10m --tail 100 app node-exporter cadvisor
docker compose exec prometheus wget -qO- http://app:5000/metrics
docker compose exec prometheus wget -qO- http://node-exporter:9100/metrics
docker compose exec prometheus wget -qO- http://cadvisor:8080/metrics
```

Run only the `wget` command for the target that is DOWN. These requests use
Compose service names on the internal network; `localhost` inside Prometheus
would refer to Prometheus itself.

**Fix:** restore the stopped service with `docker compose up -d <service>`.
For connection-refused or DNS errors, compare the target with
`prometheus/prometheus.yml` and the service/port in `docker-compose.yml`.
After editing Prometheus configuration, validate and restart:

```powershell
docker compose run --rm --no-deps --entrypoint promtool prometheus check config /etc/prometheus/prometheus.yml
docker compose restart prometheus
```

For Flask, verify `/metrics` directly and inspect app logs. For cAdvisor on
this Docker Desktop setup, inspect its logs and confirm its containerd socket
mount is present. For Node Exporter, check that it responds on port 9100.

**Verify recovery:** the target shows UP, its Last scrape is recent, and a
known metric such as `up{job="flask-app"}` returns `1` in the Prometheus
query page.

## Scenario 3: Grafana cannot connect to Prometheus

**Impact:** dashboards show datasource errors or No data even while Prometheus
is collecting samples.

**Likely causes:** the datasource URL is set to `localhost:9090` from inside
Grafana, Prometheus is down, or provisioning contains an invalid URL.

**Investigate in PowerShell:**

```powershell
docker compose ps grafana prometheus
docker compose logs --since 10m --tail 100 grafana
docker compose logs --since 10m --tail 100 prometheus
docker compose exec grafana wget -qO- http://prometheus:9090/-/ready
Invoke-RestMethod http://localhost:9090/-/ready
```

**Fix:** open Grafana **Connections → Data sources → Prometheus** and set the
server URL to `http://prometheus:9090`, the Compose service DNS name. The
provisioned source is configured in
`grafana/provisioning/datasources/prometheus.yml`; correct it there so the
configuration survives container recreation, then apply it:

```powershell
docker compose restart grafana
```

Do not use `http://localhost:9090` in Grafana's datasource: localhost there
means the Grafana container, not the Windows host or Prometheus container.

**Verify recovery:** Grafana's datasource page reports a successful
connection, and the Explore view returns samples for `up`.

## Scenario 4: Docker container consumes excessive memory

**Impact:** the container may become slow or be killed under memory pressure;
other containers can also be affected.

**Likely causes:** a leak, unbounded in-memory work, excessive concurrency, or
a workload larger than the available Docker Desktop VM memory.

**Investigate in PowerShell:**

```powershell
docker stats --no-stream
docker compose ps
docker compose logs --since 10m --tail 100 app
docker inspect (docker compose ps -q app) --format '{{.State.OOMKilled}} {{.State.ExitCode}}'
```

In Prometheus, query working-set bytes by image:

```promql
sum by (image) (container_memory_working_set_bytes{image!=""}) / 1024 / 1024
```

Check Linux VM available memory with `node_memory_MemAvailable_bytes` and
`node_memory_MemTotal_bytes`. cAdvisor's container labels on this setup may
use generated IDs; match them to the current `docker compose ps -q` output.

**Fix:** find the code path or workload causing growth from logs and
application behavior, bound queues/caches/concurrency, and rebuild. A
container memory limit can protect the host, but it does not fix a leak; add a
limit only after choosing a realistic value for the workload. Restarting a
container can restore service temporarily but loses the evidence and does not
remove the underlying cause.

**Verify recovery:** `docker stats --no-stream` and the PromQL series show
stable memory over several minutes, the container remains running, and its
logs show no OOM termination.

## Scenario 5: CPU utilization reaches 90%

**Impact:** requests may slow down, time out, or queue while the Linux VM has
little CPU capacity left.

**Likely causes:** high request volume, inefficient or repeated work, a
runaway process, or Docker Desktop VM resource limits.

**Investigate:** check the `HighCPUUsage` rule at
<http://localhost:9090/alerts> and query Linux host CPU use:

```promql
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

Check container CPU in PowerShell with `docker stats --no-stream`, then
compare over time. Query cAdvisor CPU cores by image:

```promql
topk(5, sum by (image) (rate(container_cpu_usage_seconds_total{image!=""}[5m])))
```

Review app request rates and errors alongside CPU. If the app's CPU is high,
look at recent code/configuration changes and request patterns. If a different
container is high, inspect that service's logs and workload.

**Fix:** address the expensive request or runaway process, reduce avoidable
work, and adjust concurrency or capacity only after confirming the cause. Do
not treat a brief spike as a sustained incident; this alert requires 90% for
five minutes, followed by the rule's 5-minute rate window.

**Verify recovery:** CPU falls below the threshold in Prometheus and the
`HighCPUUsage` alert clears after the expression and pending duration resolve.

## Scenario 6: Disk utilization reaches 90%

**Impact:** writes, logs, or container operations can fail when a filesystem
runs out of space.

**Likely causes:** growing Docker images/layers, logs, Prometheus time-series
retention, generated reports, or application data.

**Investigate safely:** this alert measures eligible filesystems in Docker
Desktop's Linux VM, not the Windows C: drive. Check its Prometheus samples:

```promql
100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs|fuse.*|9p|proc|sysfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs|fuse.*|9p|proc|sysfs"})
```

In PowerShell inspect Docker usage and project report files:

```powershell
docker system df
Get-ChildItem reports -Force | Select-Object Name,Length
docker compose exec prometheus df -h /prometheus
```

`docker system df` is informational. Do not run `docker system prune` as a
first response: it can remove images or caches needed for recovery. Do not
fill the filesystem to test this alert.

**Fix:** identify which mount is full, then remove only known disposable
artifacts or old generated reports after confirming they are not needed.
Review Prometheus retention and disk allocation before changing retention or
deleting its data volume. If the full mount is the Windows host drive, free
space using Windows storage tools; the Node Exporter alert may not represent
that host drive.

**Verify recovery:** available bytes increase and the matching filesystem
usage query falls below 90%. The alert clears after its 5-minute pending
period and evaluation delay.

## Scenario 7: Trivy detects a critical vulnerability

**Impact:** the image may contain a package or dependency with a known
critical weakness. Do not deploy it until the finding is reviewed and
remediated or a narrow, documented exception is approved.

**Investigate in Git Bash at the project root:**

```bash
bash scripts/security-scan.sh
```

The script gates HIGH and CRITICAL results and exits nonzero for findings or
scanner failures. Inspect the generated `reports/image-scan.txt`,
`reports/dependency-scan.txt`, and corresponding JSON files if present. The
image scan covers OS packages, supported application libraries, and secrets;
the filesystem scan checks the Python dependency tree. A report is only
available if that scan completed. The Dockerfile configuration report is
separate and does not prove vulnerability scanning succeeded.

**Procedure and fix:** record the CVE, package, installed and fixed versions,
severity, and affected artifact. Check whether it is reachable/used and read
the vendor advisory. Upgrade the Python dependency in
`app/requirements.txt` or update the base image reference in
`app/Dockerfile` to a patched supported release. Rebuild and rerun the scan:

```bash
docker compose build --no-cache app
bash scripts/security-scan.sh
```

If no fixed release exists, document the precise CVE, rationale, compensating
controls, owner, and expiry in a reviewed exception process. Do not broadly
ignore all critical findings. If Trivy cannot download its vulnerability
database, treat the scan as **incomplete**, not clean; restore registry access
or configure an approved reachable Trivy database mirror before making a
deployment decision.

**Verify recovery:** the rebuilt image has a new digest, the completed scan
reports no unexcepted HIGH/CRITICAL findings, and the script exits `0`. A
nonzero result caused by database/network failure is not a successful
verification.

## Practice safely

The application exposes `/api/error` for the controlled HTTP error alert. The
alerting guide documents how to trigger it and how to stop/restart the app for
availability alerts. Avoid filling disks, generating uncontrolled memory
pressure, or stopping shared services on a machine used for other work. For
CPU, memory, and disk alert testing, temporarily lower the corresponding rule
threshold in a disposable local checkout, validate/restart Prometheus, observe
the rule, then restore the original rule and validate it again.
