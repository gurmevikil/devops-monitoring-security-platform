# Phase 8: Prometheus alerting

## Rule behavior

Prometheus reads `prometheus/alert_rules.yml` through
`prometheus/prometheus.yml`. It evaluates each group every 15 seconds. A rule
enters **Pending** when its expression is true; it becomes **Firing** after its
`for` duration remains true. It returns to **Inactive** after the expression
stops matching.

| Alert | Condition | Pending period | Severity |
| --- | --- | ---: | --- |
| `ApplicationDown` | Flask scrape target is down | 30 seconds | Critical |
| `HighHTTPErrorRate` | HTTP 5xx fraction exceeds 5% over a 5-minute rate window | 1 minute | Warning |
| `HighCPUUsage` | Linux VM CPU use exceeds 90% | 5 minutes | Warning |
| `HighMemoryUsage` | Linux VM memory use exceeds 90% | 5 minutes | Warning |
| `HighDiskUsage` | Eligible filesystem use exceeds 90% | 5 minutes | Warning |
| `ContainerDown` | cAdvisor has no series for the expected Flask image or its last-seen timestamp is over 60 seconds old | 1 minute | Critical |

The disk rule excludes pseudo filesystems and Windows-shared WSL mounts such as
`9p`, `/mnt/host`, and `/usr/lib/wsl`; otherwise these can create false alerts
on Docker Desktop. The CPU, memory, and disk rules describe the Linux VM
monitored by Node Exporter, not Windows host counters.

## View rules and alerts

Open <http://localhost:9090/alerts> to see each rule's state and pending timer.
Open **Status → Rules** to inspect expressions and labels. Prometheus evaluates
and displays alerts locally. This project does not configure Alertmanager or a
notification receiver, so it does not send email, chat, pager, or other
notifications.

## Trigger the HTTP error-rate alert

With the stack running, run in PowerShell from the project folder. The endpoint
intentionally returns HTTP 500; the `catch` block keeps those expected demo
responses from interrupting the loop.

```powershell
1..20 | ForEach-Object {
  try { Invoke-WebRequest -Uri http://localhost:5000/api/error -UseBasicParsing | Out-Null }
  catch { }
}
```

After about one minute, refresh <http://localhost:9090/alerts>. `HighHTTPErrorRate`
should move from Pending to Firing. The request counters use a five-minute
rate window, so the test signal fades gradually rather than disappearing
immediately. On a fresh Prometheus database, the first error request creates
the `http_errors_total` series; `rate()` needs two scrapes before it can
calculate a rate. If the alert remains inactive after the first burst, wait
for a scrape interval and send another burst.

## Trigger application and container down alerts

This briefly stops the sample app. Run these commands in PowerShell from the
project folder, and restart it promptly after checking the alert:

```powershell
docker compose stop app
```

After roughly 30–45 seconds, `ApplicationDown` should be Firing. If cAdvisor
stops reporting the expected app image, `ContainerDown` should follow after
about one minute. Restore the service:

```powershell
docker compose start app
docker compose ps app
```

The app should return to `healthy`; the alerts clear after Prometheus observes
the recovered target and container metrics.

## Verify the rule file

From PowerShell in the project folder:

```powershell
docker compose run --rm --no-deps --entrypoint promtool prometheus check config /etc/prometheus/prometheus.yml
```

`promtool` should report a valid Prometheus configuration and six rules. After
editing the rule file, restart Prometheus to reload it:

```powershell
docker compose restart prometheus
```

## Troubleshooting

- If a rule is absent from **Status → Rules**, validate the file with
  `promtool`, confirm `rule_files` in `prometheus.yml`, then restart Prometheus.
- If a rule stays Pending, the expression may be true but its `for` period has
  not elapsed. Check the matching PromQL expression in the Prometheus graph.
- If `ApplicationDown` does not fire, check that the `flask-app` target is
  actually down and allow for its 30-second pending period.
- If `ContainerDown` does not fire when the app is stopped, inspect
  `container_last_seen` labels in Prometheus and adjust the expected image
  selector to match the image tag used by Compose.
- A firing alert is not evidence that anyone received a notification. Add and
  test an Alertmanager receiver separately before claiming delivery.

