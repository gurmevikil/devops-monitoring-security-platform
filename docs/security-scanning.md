# Phase 9: Trivy security scanning

## Version and scan scope

The project uses Trivy `0.76.1`, a pinned stable release. Pinning avoids
unexpected scanner/database behavior changes when the project is rerun. Trivy
scans the built image for OS package and application-library vulnerabilities,
as well as embedded secrets. A filesystem scan checks the Python dependency
manifest. A configuration scan checks `app/Dockerfile` for supported
misconfigurations. Trivy's built-in Docker misconfiguration scanner supports
Dockerfiles; it does not currently scan Compose YAML as a Docker misconfiguration
target. See [Trivy installation](https://trivy.dev/docs/latest/getting-started/installation/),
[image scanning](https://trivy.dev/docs/latest/guide/target/container_image/),
and [Docker configuration coverage](https://trivy.dev/docs/latest/coverage/iac/docker/).

The agreed deployment gate is **HIGH** and **CRITICAL**. A finding at either
severity, or a scanner execution error, makes the script exit with status `1`.
Reports are written to `reports/` and ignored by Git so local scan output does
not accumulate in commits.

## Trivy in Docker Desktop

The Bash script uses the official pinned `aquasec/trivy:0.76.1` image, so a
separate Windows Trivy installation is not needed. It mounts the Docker Engine
socket so Trivy can read the locally built image, and mounts the project and
cache directories so reports persist on the host. Access to the Docker socket
is highly privileged; only run the script on a trusted development machine.
Verify Docker Desktop and pull the scanner image in PowerShell:

```powershell
docker pull aquasec/trivy:0.76.1
docker run --rm aquasec/trivy:0.76.1 version
docker image inspect devops-monitoring-app:1.0.0
```

The first vulnerability scan downloads Trivy's database; it needs access to a
supported registry. This workstation cannot reach Trivy's default Google
mirror or the Docker Hub registry reliably, so the script defaults to
`mirror.gcr.io/aquasec/trivy-db`, which was reachable from the project network.
Set `TRIVY_DB_REPOSITORY` in Git Bash to use another supported Trivy DB mirror
if needed. If your network requires an HTTP(S)
proxy, configure Docker Desktop's container proxy for image pulls and export
`HTTPS_PROXY` (and `HTTP_PROXY`/`NO_PROXY` if required) in Git Bash before the
scan; the script passes configured proxy variables into the Trivy container.
Use the proxy address supplied by your network administrator, and do not
commit proxy credentials. Later scans reuse `.trivy-cache/` in the
project folder. If the image scan cannot obtain the vulnerability database,
the dependency scan is skipped (it needs the same database), while the
Dockerfile configuration scan still runs with Trivy's embedded checks when
the remote checks bundle is unreachable. Docker Desktop
must expose its Linux engine socket at `/var/run/docker.sock` inside
containers, as it does for the cAdvisor service in this project. The Compose
default network is IPv6-only on this workstation, and the scan container joins
that network. Start the stack before scanning so the script can select the
network. Override it with `TRIVY_NETWORK` only when using a different network.
The script allows a 30-minute scan timeout for the slow registry connection;
override it with `TRIVY_TIMEOUT` in Git Bash if needed. Trivy's official
database locations are listed in the
[Trivy database documentation](https://trivy.dev/docs/latest/guide/configuration/db/).

## Run scans

From Git Bash at the repository root, start the project network and run:

```bash
docker compose up --build --detach
bash scripts/security-scan.sh
```

The default image is `devops-monitoring-app:1.0.0`. Pass another local image
tag as the first argument if needed:

```bash
bash scripts/security-scan.sh my-app:dev
```

When a scan completes, the script creates its JSON and table reports:

- `reports/image-scan.json` and `reports/image-scan.txt`
- `reports/dependency-scan.json` and `reports/dependency-scan.txt`
- `reports/config-scan.json`

The `.json` files are complete machine-readable findings. The `.txt` files
for image and dependency scans are filtered to HIGH and CRITICAL findings for
quick review. Dockerfile misconfiguration results are kept as JSON because
Trivy's `convert --format table` does not render these configuration results.
An empty result or `PASS` means no HIGH/CRITICAL finding was reported by that
completed scan; it does not prove the software has no vulnerabilities.

## Latest scan result

On 2026-11-02, the complete scan succeeded technically after the Trivy database
was reachable, but the security gate correctly returned exit code `1`: the
image report contains 45 HIGH package matches across 9 unique Debian CVEs and
no CRITICAL matches. Trivy listed no fixed package version for any of those
45 matches. The Python requirements scan reported no HIGH/CRITICAL findings;
the Dockerfile scan passed 20 checks with 0 failures. The package matches
repeat a small set of CVEs across related Debian packages, so 45 is not 45
distinct vulnerabilities.

The build now uses the current pinned Python 3.12 Trixie image and upgrades
Debian packages from the security repository. A rebuild installed the latest
available packages, but Debian currently marks examples such as ncurses as
`no DSA` and the listed util-linux and SQLite issues as vulnerable for Trixie.
Those advisories have no available patched package in the configured
repository at scan time. Keep the gate enabled and rerun after Debian publishes
updates; do not hide these findings with a blanket ignore rule. See the
[Debian ncurses tracker](https://security-tracker.debian.org/tracker/CVE-2025-69720),
[Debian util-linux tracker](https://security-tracker.debian.org/tracker/source-package/util-linux),
and [Debian SQLite tracker](https://security-tracker.debian.org/tracker/source-package/sqlite3).

## Understand a finding

A CVE is a public identifier for a disclosed software vulnerability. Trivy
matches installed OS packages and supported application dependencies against
its vulnerability database, reports severity, installed version, fixed
version when known, and an advisory reference. Fixes usually mean updating the
base image or dependency to a supported patched version, rebuilding the image,
and rescanning it. A Dockerfile misconfiguration is a risky build instruction
or image setup detected by policy checks; use the rule ID and remediation text
in the report to decide what to change.

Review false positives against the exact package, version, platform, and
upstream advisory. Prefer updating or removing the affected component. If a
finding must be excepted, document its CVE or rule ID, reason, compensating
controls, owner, and expiry in a reviewed policy file; do not broadly suppress
all HIGH/CRITICAL findings or edit generated reports as if that fixed the issue.

## Verify the gate

`0` means all three scans completed with no HIGH/CRITICAL findings. `1` means
the configured threshold was exceeded, a required scan was skipped, or a
scanner failed; inspect the logs and generated JSON files to tell which. A
vulnerability scan that cannot download its database cannot produce its
report. The Dockerfile check can still produce a report from embedded checks.
`2` means the expected local image was missing. Completed scan reports are
generated even when findings make the overall scan fail.

This project does not yet configure GitHub Actions. The same script can be
called in CI after the image build; configure the workflow to fail on its
nonzero exit code and store reports as build artifacts rather than committing
them.

