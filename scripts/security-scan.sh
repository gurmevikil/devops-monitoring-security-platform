#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IMAGE="${1:-devops-monitoring-app:1.0.0}"
SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"
TRIVY_IMAGE="aquasec/trivy:0.76.1"
REPORT_DIR="/workspace/reports"
HOST_REPORT_DIR="$ROOT_DIR/reports"
HOST_ROOT="$(cygpath -w "$ROOT_DIR")"
HOST_CACHE="$HOST_ROOT/.trivy-cache"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker CLI is required to verify the local image." >&2
  exit 127
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "ERROR: Local image '$IMAGE' was not found. Build it with: docker compose build app" >&2
  exit 2
fi

TRIVY_NETWORK="${TRIVY_NETWORK:-}"
if [[ -z "$TRIVY_NETWORK" ]]; then
  APP_CONTAINER="$(docker compose ps -q app)"
  if [[ -z "$APP_CONTAINER" ]]; then
    echo "ERROR: Start the Compose stack first so Trivy can use its IPv6-enabled network: docker compose up -d" >&2
    exit 2
  fi
  TRIVY_NETWORK="$(docker inspect --format '{{range $name, $network := .NetworkSettings.Networks}}{{$name}}{{end}}' "$APP_CONTAINER")"
fi

if ! docker image inspect "$TRIVY_IMAGE" >/dev/null 2>&1; then
  echo "Pulling pinned Trivy image $TRIVY_IMAGE"
  docker pull "$TRIVY_IMAGE"
fi

mkdir -p "$ROOT_DIR/.trivy-cache" "$HOST_REPORT_DIR"

run_trivy() {
  local proxy_args=()
  local variable
  for variable in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
    if [[ -n "${!variable:-}" ]]; then
      proxy_args+=(--env "$variable")
    fi
  done

  MSYS_NO_PATHCONV=1 docker run --rm \
    --network "$TRIVY_NETWORK" \
    --env "TRIVY_DB_REPOSITORY=${TRIVY_DB_REPOSITORY:-aquasec/trivy-db}" \
    "${proxy_args[@]}" \
    --mount "type=bind,source=$HOST_ROOT,target=/workspace" \
    --mount "type=bind,source=$HOST_CACHE,target=/root/.cache" \
    --mount "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock" \
    --workdir /workspace \
    "$TRIVY_IMAGE" "$@"
}

image_status=0
dependency_status=0
config_status=0

convert_report() {
  local report_name="$1"
  if [[ -f "$HOST_REPORT_DIR/$report_name.json" ]]; then
    run_trivy convert --format table --severity "$SEVERITY" \
      --output "$REPORT_DIR/$report_name.txt" "$REPORT_DIR/$report_name.json"
  else
    echo "WARN: $report_name.json was not produced because its scan could not complete." >&2
  fi
}

echo "Scanning image vulnerability and embedded-secret findings: $IMAGE"
if run_trivy image \
  --scanners vuln,secret \
  --severity "$SEVERITY" \
  --format json \
  --output "$REPORT_DIR/image-scan.json" \
  --exit-code 1 \
  "$IMAGE"; then
  image_status=0
else
  image_status=$?
fi
convert_report image-scan

if [[ -f "$HOST_REPORT_DIR/image-scan.json" ]]; then
  echo "Scanning Python dependency vulnerability findings in app/requirements.txt"
  if run_trivy fs \
    --scanners vuln \
    --severity "$SEVERITY" \
    --format json \
    --output "$REPORT_DIR/dependency-scan.json" \
    --exit-code 1 \
    app; then
    dependency_status=0
  else
    dependency_status=$?
  fi
  convert_report dependency-scan
else
  dependency_status=1
  echo "WARN: dependency scan skipped because the image scan could not download the vulnerability database." >&2
fi

echo "Scanning Dockerfile misconfigurations"
if run_trivy config \
  --misconfig-scanners dockerfile \
  --severity "$SEVERITY" \
  --format json \
  --output "$REPORT_DIR/config-scan.json" \
  --exit-code 1 \
  app/Dockerfile; then
  config_status=0
else
  config_status=$?
fi
echo "Dockerfile configuration findings are available in reports/config-scan.json."

echo "Reports saved under reports/ (ignored by Git)."
if (( image_status != 0 || dependency_status != 0 || config_status != 0 )); then
  echo "FAIL: scan errors or findings at severity $SEVERITY need review before deployment." >&2
  exit 1
fi

echo "PASS: no findings at severity $SEVERITY were reported by the completed scans."
