#!/usr/bin/env bash
# One-shot orchestrator for the AmabileAI Observability deploy (DEV/PoC Railway env).
#
# Runs, in order:
#   ITEM 3  -> scripts/deploy-fix.sh   (ClickHouse self-heal rebuild + backend redeploy)
#   VERIFY  -> scripts/verify-fix.sh   (public health + no REPLICA_ALREADY_EXISTS)
#   ITEM 2  -> scripts/item2-tyk-cloudflare.sh  (Tyk API + Cloudflare CNAME) — ONLY if VERIFY passes
#
# Tokens are loaded from scripts/.deploy.env (gitignored). Just run:
#   bash scripts/run-all.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="$REPO_ROOT/scripts/.deploy.env"
[ -f "$ENV_FILE" ] || { echo "FATAL: $ENV_FILE not found (create it with the deploy tokens)."; exit 1; }
# Load + auto-export every var defined in the env file.
set -a; . "$ENV_FILE"; set +a

: "${RAILWAY_API_TOKEN:?RAILWAY_API_TOKEN missing in scripts/.deploy.env}"

hr() { printf '\n========================================================================\n%s\n========================================================================\n' "$1"; }

hr "ITEM 3 — ClickHouse self-heal deploy + backend migration"
bash "$REPO_ROOT/scripts/deploy-fix.sh" || { echo "FATAL: item 3 (deploy-fix.sh) failed. See scripts/RUNBOOK-item3.md / rollback-fix.sh"; exit 1; }

hr "VERIFY — post-deploy health checks"
if bash "$REPO_ROOT/scripts/verify-fix.sh"; then
  VERIFY_OK=1
else
  VERIFY_OK=0
  echo ">>> VERIFY FAILED — NOT proceeding to item 2 (Tyk/Cloudflare)."
  echo ">>> Inspect backend logs; if REPLICA_ALREADY_EXISTS persists, follow scripts/RUNBOOK-item3.md."
  exit 1
fi

hr "ITEM 2 — Route observability via Tyk + Cloudflare DNS (additive, no cutover)"
bash "$REPO_ROOT/scripts/item2-tyk-cloudflare.sh" || { echo "FATAL: item 2 failed. Rollback: DELETE /tyk/apis/{id} + reload, delete CNAME (see scripts/RUNBOOK-item2.md)"; exit 1; }

hr "ALL DONE — item 3 deployed & verified, item 2 (Tyk route) created. Review scripts/RUNBOOK-item2.md for optional cutover."
