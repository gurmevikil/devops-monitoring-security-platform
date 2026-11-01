# Phase 7: Grafana dashboards

## How the connection works

Grafana is published at <http://localhost:3000>. It connects to Prometheus at
`http://prometheus:9090` over the private Compose network. The provisioning
files in `grafana/provisioning/` configure the data source and load dashboard
JSON from `grafana/dashboards/` at startup. The Grafana database is kept in the
`grafana-data` named volume.

The stack pins Grafana OSS `13.3.0`, a stable release published October 27,
2026. The project pins a specific tag so dashboard behavior does not silently
change when the stack is recreated. See the [official Grafana download page](https://grafana.com/grafana/download?pl=null&platform=docker).

## Set the local login password

The repository contains `.env.example` with a placeholder. Copy it to `.env`,
replace the placeholder with a unique local password, then start the stack:

```powershell
Copy-Item .env.example .env
notepad .env
docker compose up --detach
```

The actual `.env` file is ignored by Git. Keep its password private. The
Grafana username defaults to `admin` and can be changed with
`GRAFANA_ADMIN_USER` in `.env`.

## Open the dashboards

Browse to <http://localhost:3000>, sign in with the username and password in
`.env`, then open **Dashboards → DevOps Monitoring**. The folder contains:

- **Application Monitoring:** request rate by status, p95 request latency,
  server-error percentage, application availability, and requests by endpoint.
- **Linux System Monitoring:** CPU utilization, memory used, filesystem used,
  and network throughput from Node Exporter.
- **Docker Container Monitoring:** CPU cores and working-set memory by image,
  plus a top-five memory table. The image variable lets you filter to one image.

Each dashboard refreshes every 15 seconds and defaults to the past hour. The
system dashboard reports the Linux VM used by Docker Desktop on Windows; it
does not report Windows host performance counters.

## Panel queries and thresholds

The application dashboard uses Prometheus counters and the request-duration
histogram. Its server-error panel is a percentage of requests; its p95 panel is
in seconds. The system dashboard shows CPU, memory, and disk as percentages,
with warning thresholds around 75–80% and critical thresholds at 90%. The
container dashboard shows CPU in cores and memory in bytes. Memory panel
thresholds are examples for this small local lab; tune them to the actual
container limits in a production service.

Provisioned dashboards are editable in Grafana, but the JSON files in Git are
the source of truth. To keep a UI change, export the dashboard JSON and update
the matching file under `grafana/dashboards/`.

The Docker Desktop/containerd cAdvisor setup in this project currently exposes
per-container CPU and memory but not per-container network counters. Therefore
the container dashboard does not imply that per-container network monitoring
is available on this workstation. See [container monitoring](container-monitoring.md)
for the verified limitation and local `docker stats` alternative.

