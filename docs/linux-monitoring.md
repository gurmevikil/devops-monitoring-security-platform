# Phase 5: Linux monitoring with Node Exporter

## What Node Exporter does

Node Exporter reads host and kernel statistics from Linux interfaces such as
`/proc` and `/sys`, then exposes them as Prometheus metrics on port `9100`.
Prometheus scrapes it through the Compose service name `node-exporter`.

This project runs on Windows 11 with Docker Desktop. Linux containers run inside
Docker Desktop's Linux VM, so the Node Exporter metrics shown here describe that
Linux environment. They do not represent Windows performance counters. A
Windows host dashboard would use Microsoft's `windows_exporter` as an optional
extension.

## Verify the exporter

From PowerShell in the project folder:

```powershell
docker compose ps node-exporter prometheus
Invoke-RestMethod http://localhost:9100/metrics | Select-String '^node_cpu_seconds_total|^node_memory_MemTotal_bytes|^node_filesystem_size_bytes|^node_network_receive_bytes_total|^node_time_seconds|^node_boot_time_seconds'
```

In Prometheus, open <http://localhost:9090/targets>. The `node-exporter` target
should be `UP`. Run the queries below in <http://localhost:9090/graph> and click
**Execute**. Prometheus evaluates each expression against the most recent
scrapes; range functions need a few samples before they show useful values.

## Useful PromQL queries

### CPU utilization

```promql
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

`node_cpu_seconds_total` is a counter of CPU time, split by `mode`. `rate(...[5m])`
estimates the per-second change over five minutes. Average idle time across CPU
cores, subtract it from one, and convert the result to a percentage. A brief
spike is less useful than a sustained rise, so production alerts normally use a
pending period.

### Memory utilization

```promql
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

`MemAvailable` estimates memory that can be allocated without swapping. This is
usually more useful for capacity monitoring than treating all filesystem cache
as unavailable memory.

### Filesystem space used

```promql
100 * (
  1 - node_filesystem_avail_bytes{
    fstype!~"tmpfs|overlay|squashfs|fuse.*|9p|proc|sysfs",
    mountpoint!~"/proc(/.*)?|/sys(/.*)?|/dev(/.*)?|/run(/.*)?|/mnt/host.*|/usr/lib/wsl.*|/var/lib/docker.*"
  }
  /
  node_filesystem_size_bytes{
    fstype!~"tmpfs|overlay|squashfs|fuse.*|9p|proc|sysfs",
    mountpoint!~"/proc(/.*)?|/sys(/.*)?|/dev(/.*)?|/run(/.*)?|/mnt/host.*|/usr/lib/wsl.*|/var/lib/docker.*"
  }
)
```

This returns one series per filesystem. Inspect its `device` and `mountpoint`
labels before setting alerts so temporary and pseudo filesystems do not create
noise. For a dashboard, filter to the filesystem you care about.

### Disk I/O busy time

```promql
100 * rate(node_disk_io_time_seconds_total[5m])
```

This estimates the percentage of time each block device was doing I/O. It is
not disk space usage. For throughput, use:

```promql
rate(node_disk_read_bytes_total[5m])
rate(node_disk_written_bytes_total[5m])
```

Set the panel unit to bytes/sec for throughput. Disk busy time can be affected
by device and kernel behavior, so use it alongside latency and application
signals when troubleshooting.

### Network traffic

```promql
rate(node_network_receive_bytes_total{device!="lo"}[5m])
rate(node_network_transmit_bytes_total{device!="lo"}[5m])
```

These show receive and transmit bytes per second by network interface. Excluding
`lo` removes loopback traffic; use interface labels to identify the interface
that carries the workload.

### System uptime

```promql
node_time_seconds - node_boot_time_seconds
```

This returns uptime in seconds. A sudden drop usually means the monitored Linux
environment restarted.

### Exporter availability

```promql
up{job="node-exporter"}
```

`1` means the last scrape succeeded; `0` means Prometheus could not scrape the
exporter. `up` measures scrape reachability, while the resource metrics describe
the system being monitored.

## Troubleshooting

- If the target is `DOWN`, check `docker compose ps node-exporter` and
  `docker compose logs --tail 50 node-exporter`.
- Confirm Prometheus targets `node-exporter:9100`, not `localhost:9100`.
- If metrics appear but describe the wrong machine, remember that Docker
  Desktop exposes the Linux VM environment. Use a native Linux host or a
  Windows-specific exporter when you need Windows host metrics.
- Use `docker compose restart node-exporter prometheus` after changing service
  or scrape configuration.

## Verified in this workspace

Prometheus returned non-empty series for CPU utilization, memory utilization,
filesystem use, disk I/O, network receive rate, and uptime. The values are from
Docker Desktop's Linux environment and can differ from Windows Task Manager.
