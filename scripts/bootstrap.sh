#!/usr/bin/env bash
# Bootstrap Railway project for opik-amabile. Idempotent.
#
# Required env:
#   RAILWAY_TOKEN  (account-scoped token from Notion: 94dfd4f3-da6b-4fa2-a0f0-202180889773)
#
# Optional:
#   RAILWAY_BIN    path to railway binary (default: railway)
#   PROJECT_NAME   default: opik-amabile

set -euo pipefail

: "${RAILWAY_TOKEN:?RAILWAY_TOKEN env var required}"
RAILWAY_BIN="${RAILWAY_BIN:-railway}"
PROJECT_NAME="${PROJECT_NAME:-opik-amabile}"
ENV_NAME="${ENV_NAME:-production}"

echo ">>> railway whoami"
$RAILWAY_BIN whoami

echo ">>> create or link project: $PROJECT_NAME"
if ! $RAILWAY_BIN status --json 2>/dev/null | grep -q "$PROJECT_NAME"; then
  $RAILWAY_BIN init --name "$PROJECT_NAME"
fi

# --- Database services (templates) ----------------------------------------
echo ">>> add MySQL"
$RAILWAY_BIN add --database mysql --service mysql || echo "  (mysql may already exist)"

echo ">>> add Redis"
$RAILWAY_BIN add --database redis --service redis || echo "  (redis may already exist)"

# --- Docker image services -------------------------------------------------
add_image_service() {
  local name="$1"
  local image="$2"
  echo ">>> add service $name (image=$image)"
  $RAILWAY_BIN add --service "$name" --image "$image" || echo "  ($name may already exist)"
}

add_image_service zookeeper       "zookeeper:3.9.4"
add_image_service minio           "bitnamilegacy/minio:2025.7.23-debian-12-r5"
add_image_service backend         "ghcr.io/comet-ml/opik/opik-backend:latest"
add_image_service python-backend  "ghcr.io/comet-ml/opik/opik-python-backend:latest"
add_image_service guardrails      "ghcr.io/comet-ml/opik/opik-guardrails-backend:1.7.16-1693"
add_image_service frontend        "ghcr.io/comet-ml/opik/opik-frontend:latest"

# clickhouse is built from local Dockerfile (services/clickhouse/) — added via the dashboard
# or `railway up --service clickhouse` after running this script. We add it as an empty service here.
echo ">>> add service clickhouse (build from services/clickhouse/Dockerfile after this script)"
$RAILWAY_BIN add --service clickhouse || echo "  (clickhouse may already exist)"

# --- Volumes ---------------------------------------------------------------
attach_volume() {
  local service="$1"
  local mount="$2"
  local size="$3"
  echo ">>> volume add: $service -> $mount ($size GB)"
  $RAILWAY_BIN volume add --service "$service" --mount-path "$mount" || echo "  (volume may already exist)"
}

attach_volume clickhouse  /var/lib/clickhouse          50
attach_volume minio       /data                        50
attach_volume guardrails  /root/.cache/huggingface     10
attach_volume zookeeper   /data                         2

echo ">>> bootstrap done. Next: ./scripts/set-env.sh"
