#!/usr/bin/env bash
# Verify Opik stack end-to-end.
set -uo pipefail

DOMAIN="${DOMAIN:-fabricaai.amabileai.com.br}"
BASE="https://$DOMAIN"

ok=0; fail=0
check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "[ok]   $label"
    ok=$((ok+1))
  else
    echo "[FAIL] $label"
    fail=$((fail+1))
  fi
}

check "DNS + TLS"            curl -fsSI "$BASE/"
check "frontend HTML"        curl -fsS  "$BASE/" -o /dev/null
check "backend health"       curl -fsS  "$BASE/api/v1/private/projects" -H "Comet-Workspace: ${OPIK_WORKSPACE:-default}" -H "authorization: ${OPIK_API_KEY:-unset}"
check "guardrails health"    curl -fsS  "$BASE/guardrails/healthcheck"

echo "---"
echo "ok=$ok  fail=$fail"
[ "$fail" -eq 0 ]
