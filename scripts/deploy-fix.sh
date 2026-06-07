#!/usr/bin/env bash
# Item 3 — apply the ClickHouse REPLICA_ALREADY_EXISTS self-heal and re-run backend migrations.
#
# This script contains NO secrets. Provide the Railway account token in your environment:
#   export RAILWAY_API_TOKEN=<claude-poc token from Notion>
#   bash scripts/deploy-fix.sh 2>&1 | tee /tmp/opik-deploy.log
#
# Safety: the deploy is NON-destructive. clear-opik-zk.sh only runs SYSTEM DROP REPLICA for
# tables that are ABSENT locally (orphaned znodes); the DROP DATABASE path stays gated behind
# CH_CLEAR_OPIK_DB (not set), so no trace data is wiped.
set -uo pipefail

: "${RAILWAY_API_TOKEN:?set RAILWAY_API_TOKEN in your env first}"
# Resolve repo root + an ABSOLUTE path to the CLI (needed because step 2 cd's into services/clickhouse).
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
BIN="${RAILWAY_BIN:-$REPO_ROOT/tools/railway-cli/railway.exe}"
PROJ="7ccaf972-0b24-46f2-a888-e877cb0cad7c"
ENVN="${ENV_NAME:-production}"
CH_BOOT_WAIT="${CH_BOOT_WAIT:-30}"   # seconds to wait for the CH container to boot + run self-heal
BE_BOOT_WAIT="${BE_BOOT_WAIT:-40}"   # seconds to wait for backend restart + Liquibase migration

[ -x "$BIN" ] || { echo "CLI not found / not executable at: $BIN"; exit 1; }

# Critical deploy steps must abort the run on failure; diagnostic/log steps stay non-fatal.
die() { echo "FATAL: $*" >&2; exit 1; }

echo "############ 0. whoami + link"
"$BIN" whoami || die "auth failed (check RAILWAY_API_TOKEN)"
"$BIN" link -p "$PROJ" -e "$ENVN" -s clickhouse || true   # convenience only; every call passes -p/-e/-s explicitly

echo "############ 1. BASELINE backend deploy logs (expect REPLICA_ALREADY_EXISTS)"
"$BIN" logs -s backend -d --lines 40 -p "$PROJ" -e "$ENVN" || true

echo "############ 2. DEPLOY clickhouse — rebuild with the self-heal script (non-destructive)"
# cd into services/clickhouse so `up` archives ONLY that dir and uses its railway.json
# (builder=DOCKERFILE). --ci streams build logs then exits non-zero if the build fails.
( cd "$REPO_ROOT/services/clickhouse" && "$BIN" up --service clickhouse -p "$PROJ" -e "$ENVN" --ci \
    -m "clickhouse: always-on non-destructive orphan-replica self-heal" ) \
  || die "clickhouse build/deploy FAILED — NOT redeploying backend. See scripts/rollback-fix.sh"

echo "############ 3. ClickHouse runtime logs — look for '[clear-opik-zk] reclaimed orphan replica' / 'self-heal'"
echo "   (waiting ${CH_BOOT_WAIT}s for the new container to boot and run the self-heal...)"
sleep "$CH_BOOT_WAIT"
"$BIN" logs -s clickhouse -d --lines 80 -p "$PROJ" -e "$ENVN" || true
echo ">>> If you do NOT see '[clear-opik-zk] done.' above, WAIT and re-pull these logs BEFORE step 4."
echo ">>> Residual-race guard: backend must only be redeployed once ClickHouse is healthy"
echo ">>> (Railway has no cross-service dependsOn). Set CONFIRM_CH_HEALTHY=1 to auto-proceed,"
echo ">>> otherwise this script pauses for manual confirmation."
if [ "${CONFIRM_CH_HEALTHY:-}" != "1" ]; then
  printf '>>> ClickHouse healthy and self-heal completed? Type yes to redeploy backend: '
  read -r ans
  [ "$ans" = "yes" ] || die "aborted before backend redeploy (operator did not confirm CH healthy)"
fi

echo "############ 4. REDEPLOY backend — re-run Liquibase migrations against the cleaned ClickHouse"
"$BIN" redeploy -s backend -y -p "$PROJ" -e "$ENVN" \
  || die "backend redeploy command FAILED to submit. See scripts/rollback-fix.sh"

echo "############ 5. backend deploy logs — expect NO REPLICA_ALREADY_EXISTS, migrations succeed"
echo "   (waiting ${BE_BOOT_WAIT}s for backend to restart and migrate...)"
sleep "$BE_BOOT_WAIT"
"$BIN" logs -s backend -d --lines 80 -p "$PROJ" -e "$ENVN" || true

echo "############ DONE. Now run: bash scripts/verify-fix.sh"
echo "If backend logs still show REPLICA_ALREADY_EXISTS, re-pull after another minute:"
echo "   \"$BIN\" logs -s backend -d --lines 80 -p $PROJ -e $ENVN"
echo "If it persists, follow the rollback decision tree in scripts/RUNBOOK-item3.md"
