#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required. Run this script from Git Bash or install curl." >&2
  exit 127
fi
if ! command -v python >/dev/null 2>&1; then
  echo "ERROR: Python 3 is required to inspect Prometheus target status." >&2
  exit 127
fi

APP_URL="${APP_URL:-http://localhost:5000}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
NODE_EXPORTER_URL="${NODE_EXPORTER_URL:-http://localhost:9100}"
CADVISOR_URL="${CADVISOR_URL:-http://localhost:8080}"
failures=0

check_http() {
  local name="$1"
  local url="$2"
  if curl --fail --silent --show-error --max-time 5 "$url" >/dev/null; then
    echo "PASS: $name ($url)"
  else
    echo "FAIL: $name ($url)" >&2
    failures=$((failures + 1))
  fi
}

check_prometheus_job() {
  local job="$1"
  local targets
  if ! targets="$(curl --fail --silent --show-error --max-time 5 "$PROMETHEUS_URL/api/v1/targets")"; then
    echo "FAIL: could not read Prometheus targets for job '$job'" >&2
    failures=$((failures + 1))
    return
  fi

  if printf '%s' "$targets" | python -c 'import json, sys; job=sys.argv[1]; data=json.load(sys.stdin); ts=[t for t in data["data"]["activeTargets"] if t["labels"].get("job")==job]; sys.exit(0 if ts and all(t["health"]=="up" for t in ts) else 1)' "$job"; then
    echo "PASS: Prometheus scrape job '$job' is UP"
  else
    echo "FAIL: Prometheus scrape job '$job' is absent or not UP" >&2
    failures=$((failures + 1))
  fi
}

echo "Checking local service endpoints..."
check_http "Flask health" "$APP_URL/health"
check_http "Flask metrics" "$APP_URL/metrics"
check_http "Prometheus readiness" "$PROMETHEUS_URL/-/ready"
check_http "Node Exporter metrics" "$NODE_EXPORTER_URL/metrics"
check_http "cAdvisor metrics" "$CADVISOR_URL/metrics"
check_http "Grafana health" "$GRAFANA_URL/api/health"

echo "Checking Prometheus scrape target health..."
check_prometheus_job flask-app
check_prometheus_job node-exporter
check_prometheus_job cadvisor

if (( failures > 0 )); then
  echo "Health check failed: $failures check(s) need investigation. See docs/troubleshooting.md." >&2
  exit 1
fi

echo "PASS: all configured endpoint and target checks succeeded."
