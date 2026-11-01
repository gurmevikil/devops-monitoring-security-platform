# Phase 6: Docker container monitoring

## Data flow

cAdvisor reads Linux cgroup statistics and exposes Prometheus metrics on
`/metrics`. Prometheus scrapes `cadvisor:8080` every 15 seconds. On this
Windows 11 setup, Docker Desktop runs Docker Engine inside its Linux VM and
uses the containerd image store. cAdvisor therefore reads Docker's containers
from the containerd socket instead of relying on Docker's legacy `layerdb`
metadata.

The Compose service mounts `/run/containerd/containerd.sock` read-only and
starts cAdvisor with `--containerd-namespace=moby`. The `moby` namespace is
where Docker Desktop's containerd stores Docker containers. The socket grants
cAdvisor access to container runtime metadata, so keep this configuration
limited to a trusted local development environment.

## Verify the data

In PowerShell at the project root:

```powershell
docker compose ps
docker compose logs --tail 30 cadvisor
```

Look for `Registration of the containerd container factory successfully` in
the logs. In Prometheus at <http://localhost:9090>, check **Status → Targets**
and confirm the `cadvisor` target is `UP`. A target being `UP` only confirms
scraping; query the following metrics to confirm actual container data:

```promql
container_memory_working_set_bytes{image!=""}
container_cpu_usage_seconds_total{image!=""}
```

Containerd metrics on this Docker Desktop version identify containers by image
and container ID. The container `name` label is a generated ID, not the Compose
service name. Use `docker compose ps` to match the current ID to its service.

## Useful PromQL

CPU usage in cores by image (1.0 means one fully used CPU core):

```promql
sum by (image) (rate(container_cpu_usage_seconds_total{image!=""}[5m]))
```

CPU percentage of one core by image:

```promql
100 * sum by (image) (rate(container_cpu_usage_seconds_total{image!=""}[5m]))
```

Working-set memory in MiB by image:

```promql
sum by (image) (container_memory_working_set_bytes{image!=""}) / 1024 / 1024
```

Top containers by working-set memory:

```promql
topk(5, container_memory_working_set_bytes{image!=""})
```

Top containers by CPU cores over five minutes:

```promql
topk(5, sum by (image, name) (rate(container_cpu_usage_seconds_total{image!=""}[5m])))
```

On this Docker Desktop/containerd combination, cAdvisor does not currently
export per-container network byte counters. These queries will return no
series here, which is a platform/runtime limitation rather than proof of zero
traffic:

```promql
container_network_receive_bytes_total{image!=""}
container_network_transmit_bytes_total{image!=""}
```

For a quick live network check on this Windows workstation, use
`docker stats --no-stream` in PowerShell. On a native Linux Docker host, use
the standard cAdvisor Docker socket and Docker storage mounts; then verify
network metrics in Prometheus before relying on network panels or alerts.

## Troubleshooting

- **Only `/`, `/docker`, or other cgroup paths appear:** check the cAdvisor logs
  and confirm the containerd factory registered successfully.
- **Containerd connection fails:** verify Docker Desktop is running and that
  `/run/containerd/containerd.sock` exists in the Docker Engine VM. The Compose
  bind mount is specific to Docker Desktop's Linux VM.
- **Target is `UP`, but no container samples appear:** query with
  `image!=""`; root cgroup metrics alone are not container-level verification.
- **Service labels are missing:** compare image and container ID labels with
  `docker compose ps`. cAdvisor's containerd source on this platform does not
  expose Compose service labels.
- **Network queries are empty:** use `docker stats` locally or run the stack on
  a native Linux Docker host and verify cAdvisor's network series there.

