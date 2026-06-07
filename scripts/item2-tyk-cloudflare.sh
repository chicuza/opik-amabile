#!/usr/bin/env bash
# ============================================================================
# Item 2 — Route the AmabileAI Observability (Opik) stack via the Tyk gateway,
#          + create the Cloudflare DNS for the new public hostname.
#
# ADDITIVE & NON-DESTRUCTIVE: this creates a NEW Tyk API and a NEW CNAME.
# It does NOT touch the existing direct route (fabricaai.amabileai.com.br ->
# a05sur4p.up.railway.app). Cutover/removal of the direct route is a SEPARATE,
# explicitly-flagged operator step (see RUNBOOK-item2.md "Optional cutover").
#
# NO SECRETS IN THIS FILE. Reads from env:
#   TYK_GW_SECRET          Tyk admin API secret (x-tyk-authorization header)
#   CLOUDFLARE_API_TOKEN   Cloudflare API token (Bearer)
#
# Optional overrides:
#   TYK_ADMIN_BASE   default: https://tyk-gateway-production-2e1b.up.railway.app
#   TYK_PUBLIC_BASE  default: https://api.amabileai.com.br
#   API_DEF_FILE     default: <repo>/services/tyk/opik-observability-api.json
#   LISTEN_PATH      default: /observability/   (must match API_DEF_FILE)
#   ZONE_NAME        default: amabileai.com.br
#   NEW_SUBDOMAIN    default: ""  (empty = reuse api.amabileai.com.br via /observability/;
#                                  set e.g. "obs" to ALSO create obs.amabileai.com.br -> gateway)
#   GATEWAY_CNAME_TARGET  Railway public host of the Tyk gateway, REQUIRED only when NEW_SUBDOMAIN is set
#                         (e.g. tyk-gateway-production-2e1b.up.railway.app)
# ============================================================================
set -euo pipefail

: "${TYK_GW_SECRET:?TYK_GW_SECRET required (Tyk admin API secret)}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TYK_ADMIN_BASE="${TYK_ADMIN_BASE:-https://tyk-gateway-production-2e1b.up.railway.app}"
TYK_PUBLIC_BASE="${TYK_PUBLIC_BASE:-https://api.amabileai.com.br}"
API_DEF_FILE="${API_DEF_FILE:-$REPO_ROOT/services/tyk/opik-observability-api.json}"
LISTEN_PATH="${LISTEN_PATH:-/observability/}"
ZONE_NAME="${ZONE_NAME:-amabileai.com.br}"
NEW_SUBDOMAIN="${NEW_SUBDOMAIN:-}"

[ -f "$API_DEF_FILE" ] || { echo "!! API def not found: $API_DEF_FILE" >&2; exit 1; }

tyk() {  # tyk <curl-args...> against the admin API
  curl -fsSL -H "x-tyk-authorization: $TYK_GW_SECRET" \
             -H "Content-Type: application/json" "$@"
}
cf() {   # cf <curl-args...> against the Cloudflare API
  curl -fsSL -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
             -H "Content-Type: application/json" "$@"
}
jget() { python -c "import sys,json;d=json.load(sys.stdin);print($1)"; }

echo "============================================================"
echo " Item 2 :: Tyk route + Cloudflare DNS for Opik observability"
echo " admin=$TYK_ADMIN_BASE  public=$TYK_PUBLIC_BASE"
echo " api_def=$API_DEF_FILE  listen_path=$LISTEN_PATH"
echo "============================================================"

# --- (pre) sanity: gateway admin reachable + which APIs exist -----------------
echo ">>> [0] gateway admin reachable? list current APIs (ids/listen_paths)"
tyk "$TYK_ADMIN_BASE/tyk/apis" \
  | python -c "import sys,json;
data=json.load(sys.stdin)
apis=data if isinstance(data,list) else data.get('apis',data)
for a in apis:
    d=a.get('api_definition',a)
    print('   -', d.get('api_id'), '->', d.get('proxy',{}).get('listen_path'))" \
  || { echo '!! could not list APIs — check TYK_GW_SECRET / admin base'; exit 1; }

# strip the editor _comment / _auth_token_alternative keys before POSTing
CLEAN_DEF="$(python -c "import json,sys;
d=json.load(open('$API_DEF_FILE'))
for k in list(d):
    if k.startswith('_'): d.pop(k)
print(json.dumps(d))")"
API_ID="$(printf '%s' "$CLEAN_DEF" | jget "d['api_id']")"

# --- (a) create or update the Tyk API ----------------------------------------
echo ">>> [a] does API '$API_ID' already exist?"
if tyk "$TYK_ADMIN_BASE/tyk/apis/$API_ID" >/dev/null 2>&1; then
  echo "    exists -> PUT /tyk/apis/$API_ID (idempotent update)"
  printf '%s' "$CLEAN_DEF" | tyk -X PUT "$TYK_ADMIN_BASE/tyk/apis/$API_ID" --data @- | python -m json.tool
else
  echo "    not found -> POST /tyk/apis (create)"
  printf '%s' "$CLEAN_DEF" | tyk -X POST "$TYK_ADMIN_BASE/tyk/apis" --data @- | python -m json.tool
fi

# --- (b) hot-reload the gateway group ----------------------------------------
echo ">>> [b] hot-reload: GET /tyk/reload/group"
tyk "$TYK_ADMIN_BASE/tyk/reload/group" | python -m json.tool
echo "    (reload is async; allow ~2-5s for workers to pick up the new spec)"

# --- (c) Cloudflare DNS ------------------------------------------------------
echo ">>> [c] Cloudflare: resolve zone $ZONE_NAME"
ZONE_ID="$(cf "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" | jget "d['result'][0]['id']")"
echo "    zone_id=$ZONE_ID"

if [ -z "$NEW_SUBDOMAIN" ]; then
  echo "    NEW_SUBDOMAIN empty -> reusing existing public host '$TYK_PUBLIC_BASE'"
  echo "    (api.amabileai.com.br already resolves to the gateway; route is path-based at $LISTEN_PATH)"
  echo "    No DNS change required for the path-based option. Skipping CNAME create."
else
  : "${GATEWAY_CNAME_TARGET:?GATEWAY_CNAME_TARGET required when NEW_SUBDOMAIN is set}"
  RECORD_NAME="${NEW_SUBDOMAIN}.${ZONE_NAME}"
  echo "    check existing record $RECORD_NAME (check-before-create)"
  EXISTING="$(cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_NAME" \
    | jget "(d['result'][0]['id'] if d['result'] else '')")"

  PAYLOAD="$(python -c "
import json
print(json.dumps({
  'type':'CNAME','name':'$NEW_SUBDOMAIN','content':'$GATEWAY_CNAME_TARGET',
  'proxied':True,'ttl':1,
  'comment':'Opik observability via Tyk gateway (managed by opic-amabile item2)'}))")"

  if [ -n "$EXISTING" ]; then
    echo "    exists ($EXISTING) -> PUT (idempotent)"
    cf -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$EXISTING" --data "$PAYLOAD" | python -m json.tool
  else
    echo "    not found -> POST (create proxied CNAME $RECORD_NAME -> $GATEWAY_CNAME_TARGET)"
    cf -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" --data "$PAYLOAD" | python -m json.tool
  fi
fi

# --- (d) verification --------------------------------------------------------
echo ">>> [d] verification"
ROUTE_BASE="$TYK_PUBLIC_BASE"
[ -n "$NEW_SUBDOMAIN" ] && ROUTE_BASE="https://${NEW_SUBDOMAIN}.${ZONE_NAME}"
LP_TRIMMED="${LISTEN_PATH%/}"   # /observability

ok=0; fail=0
check() { local label="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "[ok]   $label"; ok=$((ok+1));
  else echo "[FAIL] $label"; fail=$((fail+1)); fi; }

# gateway liveness (Tyk's own /hello health endpoint, no auth)
check "gateway /hello health"        curl -fsS "$TYK_ADMIN_BASE/hello"
# new route serves the Opik/AmabileAI UI through the gateway (keyless -> 200)
check "route UI 200 ($LP_TRIMMED/)"  curl -fsS "$ROUTE_BASE$LP_TRIMMED/" -o /dev/null
# backend reachable through the gateway; expect 401/403/500 WITHOUT an Opik key
#   (the gateway is keyless, so Opik's OWN app-auth is what rejects here — proves passthrough)
echo "    backend-through-gateway (expect 401/403/500 without OPIK key, NOT a Tyk 'key not authorised'):"
curl -fsS -o /dev/null -w "      HTTP %{http_code}\n" \
  "$ROUTE_BASE$LP_TRIMMED/api/v1/private/projects" \
  -H "Comet-Workspace: ${OPIK_WORKSPACE:-default}" || true
# with an Opik key, the SDK path should succeed (only if OPIK_API_KEY is exported)
if [ -n "${OPIK_API_KEY:-}" ]; then
  check "backend 200 WITH OPIK key"  curl -fsS "$ROUTE_BASE$LP_TRIMMED/api/v1/private/projects" \
    -H "Comet-Workspace: ${OPIK_WORKSPACE:-default}" -H "authorization: $OPIK_API_KEY"
else
  echo "[skip] backend WITH OPIK key (export OPIK_API_KEY to test the authenticated path)"
fi
# guardrails passthrough
check "guardrails healthcheck"       curl -fsS "$ROUTE_BASE$LP_TRIMMED/guardrails/healthcheck"

echo "---"
echo "ok=$ok  fail=$fail"
echo ">>> done. SDK override for the gateway route:"
echo "      OPIK_URL_OVERRIDE=$ROUTE_BASE$LP_TRIMMED/api"
[ "$fail" -eq 0 ]
