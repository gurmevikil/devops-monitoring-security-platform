# Project interview preparation

## 60-second project explanation

“I built a local DevOps Monitoring and Security Automation Platform with
Docker Compose. A Flask service exposes health and Prometheus metrics.
Prometheus scrapes the app, Node Exporter, and cAdvisor, stores time-series
data, and evaluates alert rules. Grafana uses Prometheus to display application,
Linux VM, and container dashboards. I added Trivy scanning with a
HIGH/CRITICAL gate, operational scripts, and troubleshooting scenarios. I
validated target health and deliberately triggered application and HTTP error
alerts. On Docker Desktop, Node Exporter monitors the Linux VM, and I documented
the cAdvisor network metric limitation. Trivy completed image, Python
dependency, and Dockerfile scans with no HIGH or CRITICAL findings. I pushed
the project to GitHub with separate commits. It has no external alert
notification receiver, and AWS deployment remains an optional extension.”

## Architecture explanation

Users call Flask over port 5000. Flask exposes `/health` for a simple health
probe and `/metrics` for counters and duration histograms. Prometheus scrapes
the app and exporters every 15 seconds, stores samples in a named volume, and
evaluates alert rules. Grafana queries Prometheus and displays provisioned
dashboards. Node Exporter describes the Docker Desktop Linux VM; cAdvisor
describes container cgroups. Trivy scans the built image, Python dependencies,
and Dockerfile configuration. Docker Compose provides service DNS and starts
the local services together.

## 25 technical questions and answers

### 1. Why did you choose Prometheus?

Prometheus is designed for time-series metrics, has a simple pull/scrape model,
supports service discovery and labels, and provides PromQL for alert
expressions and dashboard queries. It fits this small Compose lab without
requiring a separate metrics agent or commercial service. In a larger
environment I would also assess retention, high availability, federation, and
managed monitoring needs.

### 2. Why Grafana?

Grafana provides dashboards and exploration across data sources. Here it
queries Prometheus and turns metric series into charts with units, thresholds,
and time ranges. It visualizes data; it does not collect the metrics itself.

### 3. What is Node Exporter?

Node Exporter is a Prometheus exporter for host-level Linux statistics such as
CPU, memory, filesystems, and network interfaces. In this Docker Desktop lab
it observes the Linux VM that runs containers, not the Windows host.

### 4. What is cAdvisor?

cAdvisor collects container resource usage and performance data from Linux
cgroups and exposes Prometheus metrics. Here it reports CPU and memory
metrics. The Docker Desktop/containerd setup used in this project does not
expose the expected per-container network byte counters.

### 5. What is Trivy?

Trivy is a security scanner for container images, software dependencies,
secrets, and supported configuration/IaC targets. The project gates HIGH and
CRITICAL findings. Its vulnerability scans require a vulnerability database;
without that database, the result is incomplete.

### 6. What happens when the application goes down?

Prometheus's scrape of `/metrics` fails and `up{job="flask-app"}` becomes 0.
After its 30-second pending period, `ApplicationDown` fires in Prometheus.
Grafana panels may show gaps or stale data. This project has no Alertmanager
receiver, so the alert does not notify anyone externally.

### 7. How do you identify high CPU usage?

I check the `HighCPUUsage` alert, query Node Exporter's idle CPU rate to
calculate host CPU utilization, then use `docker stats` and cAdvisor's
`container_cpu_usage_seconds_total` rate to find the busy container. I compare
the time window with request rates, errors, logs, and recent changes before
deciding to scale or change code.

### 8. How do you identify high memory usage?

I check Node Exporter's available/total memory and cAdvisor's
`container_memory_working_set_bytes`, then compare with `docker stats` and
container exit/OOM state. A sustained increase suggests a leak or unbounded
work; a short-lived spike may be normal caching or a workload burst.

### 9. How do you identify Docker container issues?

I start with `docker compose ps`, `docker compose logs`, and `docker inspect`
for state, health, exit code, and OOM status. Then I inspect `docker stats`,
test the service endpoint, review Prometheus targets, and compare cAdvisor
metrics with the Compose container ID.

### 10. How do you detect vulnerabilities?

I scan the built image and dependency files with Trivy, review CVE IDs,
severity, installed and fixed versions, and vendor advisories, then update
packages/base images, rebuild, and rescan. The gate fails on HIGH and CRITICAL
findings or a scanner error. A failed database download is not a clean scan.

### 11. What is a Prometheus scrape target?

A target is an HTTP endpoint Prometheus periodically polls for metrics. The
target's `up` series is 1 if the latest scrape succeeded and 0 if it failed.
The `/targets` page shows scrape health and the last error.

### 12. What does a scrape interval control?

It sets how often Prometheus requests metrics from a target. This project uses
15 seconds. A shorter interval gives faster visibility and more samples but
increases network, CPU, and storage load.

### 13. What is PromQL?

PromQL is Prometheus's query language for selecting and aggregating time
series. For example, `rate(http_requests_total[5m])` estimates per-second
request growth over five minutes, while label filters select a target or
status code.

### 14. What is the difference between a counter and a gauge?

A counter only increases (or resets when a process restarts), such as total
requests. A gauge can increase and decrease, such as current memory usage.
Counters are commonly analyzed with `rate()` or `increase()`.

### 15. Why use a histogram for request duration?

A histogram records observations in buckets plus count and sum, so Prometheus
can estimate latency distributions and quantiles across observations. The
bucket layout matters; quantiles are estimates rather than exact per-request
percentiles.

### 16. How does a Prometheus alert move from Pending to Firing?

When the expression returns a matching series, the rule becomes Pending. If
the condition remains true for the configured `for` duration, it becomes
Firing. When the expression stops matching, it returns to Inactive after
evaluation. A group interval controls evaluation frequency.

### 17. What is the difference between Prometheus and Grafana?

Prometheus scrapes and stores metrics, evaluates PromQL, and evaluates alert
rules. Grafana queries data sources and renders dashboards. Grafana doesn't
replace Prometheus's metric collection or storage.

### 18. What does `docker compose up --build -d` do?

Compose builds images that have build configuration, creates or updates the
services and network, starts containers in the background, and returns control
to the terminal. `docker compose ps` and logs are next checks for readiness.

### 19. What is a Docker health check?

A health check runs a command inside the container at intervals and records
healthy/unhealthy status. This app probes `/health`. Health status helps
operators distinguish a running process from a responding application, but
the probe should stay lightweight and representative.

### 20. How does Docker Compose service discovery work?

Compose provides DNS names based on service names on the project network. The
Grafana container reaches Prometheus at `http://prometheus:9090`; `localhost`
inside Grafana would refer to Grafana itself.

### 21. What is a CVE and what do severity levels mean?

A CVE is a public identifier for a disclosed vulnerability. Severity is an
estimate of potential impact and exploitability; it is a prioritization input,
not a complete risk assessment. I also consider affected versions, exposure,
reachability, available fixes, and compensating controls.

### 22. How do you handle a false positive or exception?

I verify package identity and version against the upstream advisory and check
whether a fix or patched base image exists. If an exception is justified, I
record the exact CVE/rule, rationale, compensating controls, owner, and expiry
for review. I avoid broad suppressions.

### 23. What monitoring challenges did this project reveal?

Metrics may be missing despite a target being UP; labels can differ across
runtimes; host metrics can describe a VM instead of the physical host; short
rate windows need enough samples; alerts can be noisy or delayed by pending
periods; exporters and storage need resource budgets; and an alert without a
tested notification path is not an operational response system.

### 24. How would you improve this for production?

I would add TLS and authentication, network isolation, persistent and backed-up
storage, retention planning, resource limits, secret management, image
provenance and CI scanning, Alertmanager with tested receivers, runbooks,
service-level objectives, and high availability appropriate to the service.
I would validate host metrics on the actual deployment platform.

### 25. How would you extend it to AWS?

I would first choose ECS/EC2/EKS based on workload and operational needs, then
use IAM least privilege, private networking, secrets management, TLS, durable
storage, and an AWS monitoring destination or securely hosted Prometheus and
Grafana. I would test alarms and recovery paths and avoid exposing Prometheus
or exporters publicly. AWS deployment is an extension, not part of the local
implementation.
