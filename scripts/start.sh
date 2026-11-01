#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker CLI not found. Start Docker Desktop and verify PATH." >&2
  exit 127
fi
if [[ ! -f .env ]]; then
  echo "ERROR: .env is missing. Copy .env.example to .env and set a local Grafana password." >&2
  exit 2
fi

docker compose config --quiet
docker compose up --build --detach
echo "Monitoring stack started. Check status with: bash scripts/status.sh"
echo "Grafana: http://localhost:3000 | Prometheus: http://localhost:9090"
