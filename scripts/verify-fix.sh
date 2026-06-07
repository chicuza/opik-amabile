#!/usr/bin/env bash
# Item 3 — POST-DEPLOY VERIFICATION for the ClickHouse REPLICA_ALREADY_EXISTS self-heal.
#
# Contains NO secrets. Two kinds of checks:
#   A) PUBLIC HTTPS probes against https://fabricaai.amabileai.com.br (no infra token needed).
#   B) Backend deploy-log greps via the Railway CLI (needs RAILWAY_API_TOKEN; skipped if unset).
#
# Run AFTER scripts/deploy-fix.sh:
#   export RAILWAY_API_TOKEN=<account token>   # optional, enables the log greps
#   bash scripts/verify-fix.sh
#
# Exit code: 0 = all required checks passed, 1 = at least one required check failed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
BIN="${RAILWAY_BIN:-$REPO_ROOT/tools/railway-cli/railway.exe}"
PROJ="7ccaf972-0b24-46f2-a888-e877cb0cad7c"
ENVN="${ENV_NAME:-production}"
DOMAIN="${DOMAIN:-fabricaai.amabileai.com.br}"
BASE="https://$DOMAIN"

pass=0; fail=0
ok()   { echo "[ok]   $*"; pass=$((pass+1)); }
bad()  { echo "[FAIL] $*"; fail=$((fail+1)); }
warn() { echo "[warn] $*"; }

# Return the HTTP status code for a GET, or 000 on transport error.
http_code() {
  curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$1" 2>/dev/null || echo "000"
}

echo "==================================================================="
echo "A) PUBLIC HTTPS PROBES  ($BASE)"
echo "==================================================================="

# 1. /health -> expect 200
code="$(http_code "$BASE/health")"
if [ "$code" = "200" ]; then ok "/health = 200"; else bad "/health = $code (expected 200)"; fi

# 2. /api/v1/private/projects -> expect AUTH error (401/403), NOT a 500 (which would mean the
#    migration/schema is still broken). A 200 here is fine too (if unauthenticated browse allowed).
code="$(http_code "$BASE/api/v1/private/projects")"
case "$code" in
  401|403)     ok   "/api/v1/private/projects = $code (auth rejected — backend up, schema OK)" ;;
  200)         ok   "/api/v1/private/projects = 200 (backend up, schema OK)" ;;
  500|502|503) bad  "/api/v1/private/projects = $code (server/migration error — schema likely NOT migrated)" ;;
  000)         bad  "/api/v1/private/projects = transport error (DNS/TLS/down)" ;;
  *)           warn "/api/v1/private/projects = $code (unexpected; inspect manually)" ;;
esac

# 3. /guardrails/healthcheck -> expect 200
code="$(http_code "$BASE/guardrails/healthcheck")"
if [ "$code" = "200" ]; then ok "/guardrails/healthcheck = 200"; else bad "/guardrails/healthcheck = $code (expected 200)"; fi

echo
echo "==================================================================="
echo "B) BACKEND DEPLOY-LOG GREPS  (Railway CLI)"
echo "==================================================================="
if [ -z "${RAILWAY_API_TOKEN:-}" ]; then
  warn "RAILWAY_API_TOKEN not set — skipping log greps (run the public probes only)."
elif [ ! -x "$BIN" ]; then
  warn "CLI not found at $BIN — skipping log greps."
else
  LOGFILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/opik-verify-backend.log")"
  if "$BIN" logs -s backend -d --lines 200 -p "$PROJ" -e "$ENVN" >"$LOGFILE" 2>&1; then
    # 4. REPLICA_ALREADY_EXISTS must be ABSENT.
    if grep -qi "REPLICA_ALREADY_EXISTS" "$LOGFILE"; then
      bad "backend logs STILL contain REPLICA_ALREADY_EXISTS (migration not healed)"
    else
      ok "backend logs free of REPLICA_ALREADY_EXISTS"
    fi
    # 5. Liquibase success markers present.
    #    Opik/Liquibase emits one of these on a clean run. Any match counts as success.
    if grep -Eqi "Successfully (released|acquired) change log lock|liquibase: Update has been successful|ChangeSet .* ran successfully|Liquibase command 'update' was executed successfully|Running Changeset" "$LOGFILE"; then
      ok "Liquibase success/activity markers found in backend logs"
    else
      warn "no explicit Liquibase success marker in last 200 lines — pull more lines / inspect manually:"
      warn "  \"$BIN\" logs -s backend -d --lines 400 -p $PROJ -e $ENVN"
    fi
    # 6. Quick sanity: healthcheck/app-start marker.
    if grep -Eqi "Started .* in [0-9.]+s|Jersey app|is-alive|Dropwizard|Server started" "$LOGFILE"; then
      ok "backend application-start marker found"
    else
      warn "no app-start marker found in last 200 lines (may be older than the window)"
    fi
  else
    warn "could not fetch backend logs (auth/network) — rely on the public probes above."
  fi
  echo ">>> raw backend log captured at: $LOGFILE"
fi

echo
echo "==================================================================="
echo "RESULT: pass=$pass  fail=$fail"
echo "==================================================================="
[ "$fail" -eq 0 ]
