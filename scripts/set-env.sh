#!/usr/bin/env bash
# Set environment variables on every Railway service.
# Idempotent — re-runnable to update vars.
#
# Required env:
#   RAILWAY_TOKEN
#
# Optional generators (auto-generated if absent):
#   ANALYTICS_DB_PASSWORD, MINIO_SECRET_KEY, OPIK_BACKEND_INTERNAL_SECRET

set -euo pipefail

: "${RAILWAY_TOKEN:?RAILWAY_TOKEN env var required}"
RAILWAY_BIN="${RAILWAY_BIN:-railway}"

gen() { openssl rand -hex 24 2>/dev/null || head -c 48 /dev/urandom | xxd -p; }

ANALYTICS_DB_PASSWORD="${ANALYTICS_DB_PASSWORD:-$(gen)}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-$(gen)}"

setv() {
  local svc="$1"; shift
  echo ">>> $svc"
  $RAILWAY_BIN variables --service "$svc" "$@"
}

# -------- clickhouse ------------------------------------------------------
setv clickhouse \
  --set "CLICKHOUSE_DB=opik" \
  --set "CLICKHOUSE_USER=opik" \
  --set "CLICKHOUSE_PASSWORD=$ANALYTICS_DB_PASSWORD" \
  --set "CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1"

# -------- minio -----------------------------------------------------------
setv minio \
  --set "MINIO_ROOT_USER=opik" \
  --set "MINIO_ROOT_PASSWORD=$MINIO_SECRET_KEY" \
  --set "MINIO_DEFAULT_BUCKETS=public"

# -------- zookeeper -------------------------------------------------------
setv zookeeper \
  --set "ALLOW_ANONYMOUS_LOGIN=yes" \
  --set "ZOO_4LW_COMMANDS_WHITELIST=ruok,mntr,stat,srvr,conf"

# -------- backend ---------------------------------------------------------
setv backend \
  --set 'STATE_DB_PROTOCOL=jdbc:mysql://' \
  --set 'STATE_DB_URL=${{mysql.MYSQLHOST}}:${{mysql.MYSQLPORT}}/opik?createDatabaseIfNotExist=true&rewriteBatchedStatements=true' \
  --set 'STATE_DB_DATABASE_NAME=opik' \
  --set 'STATE_DB_USER=${{mysql.MYSQLUSER}}' \
  --set 'STATE_DB_PASS=${{mysql.MYSQLPASSWORD}}' \
  --set 'ANALYTICS_DB_MIGRATIONS_URL=jdbc:clickhouse://clickhouse.railway.internal:8123' \
  --set 'ANALYTICS_DB_MIGRATIONS_USER=opik' \
  --set "ANALYTICS_DB_MIGRATIONS_PASS=$ANALYTICS_DB_PASSWORD" \
  --set 'ANALYTICS_DB_PROTOCOL=HTTP' \
  --set 'ANALYTICS_DB_HOST=clickhouse.railway.internal' \
  --set 'ANALYTICS_DB_PORT=8123' \
  --set 'ANALYTICS_DB_DATABASE_NAME=opik' \
  --set 'ANALYTICS_DB_USERNAME=opik' \
  --set "ANALYTICS_DB_PASSWORD=$ANALYTICS_DB_PASSWORD" \
  --set 'REDIS_URL=redis://default:${{redis.REDIS_PASSWORD}}@redis.railway.internal:6379/' \
  --set 'PYTHON_EVALUATOR_URL=http://python-backend.railway.internal:8000' \
  --set 'OPIK_GUARDRAILS_BASE_URL=http://guardrails.railway.internal:5000' \
  --set 'OPIK_USAGE_REPORT_ENABLED=false' \
  --set 'JAVA_OPTS=-XX:MaxRAMPercentage=80' \
  --set 'MINIO_URL=http://minio.railway.internal:9000' \
  --set 'MINIO_ACCESS_KEY=opik' \
  --set "MINIO_SECRET_KEY=$MINIO_SECRET_KEY" \
  --set 'S3_BUCKET=public'

# -------- python-backend --------------------------------------------------
setv python-backend \
  --set 'OPIK_URL_OVERRIDE=http://backend.railway.internal:8080' \
  --set 'PYTHON_CODE_EXECUTOR_STRATEGY=process' \
  --set 'REDIS_URL=redis://default:${{redis.REDIS_PASSWORD}}@redis.railway.internal:6379/'

# -------- guardrails ------------------------------------------------------
setv guardrails \
  --set 'OPIK_GUARDRAILS_DEVICE=cpu' \
  --set 'CUDA_VISIBLE_DEVICES=' \
  --set 'HF_HOME=/root/.cache/huggingface'

# -------- frontend --------------------------------------------------------
setv frontend \
  --set 'OPIK_BACKEND_BASE_URL=http://backend.railway.internal:8080' \
  --set 'OPIK_GUARDRAILS_BACKEND_URL=http://guardrails.railway.internal:5000' \
  --set 'PORT=5173'

cat <<EOF >&2

SECRETS (save to Notion before closing this shell):
  ANALYTICS_DB_PASSWORD=$ANALYTICS_DB_PASSWORD
  MINIO_SECRET_KEY=$MINIO_SECRET_KEY
EOF
