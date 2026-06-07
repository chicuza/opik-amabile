#!/usr/bin/env bash
# Item 3 — ROLLBACK for the ClickHouse REPLICA_ALREADY_EXISTS self-heal deploy.
#
# Contains NO secrets. Provide the Railway account token in your environment:
#   export RAILWAY_API_TOKEN=<account token>
#   bash scripts/rollback-fix.sh <target>
#
# <target> is one of:
#   clickhouse   — the new CH build went bad; rebuild from the PREVIOUS git checkout
#   backend      — the backend redeploy went bad; roll backend back to the prior deployment
#   inspect      — (default) just list recent deployments + statuses for both services
#
# IMPORTANT facts about Railway rollback with this CLI (v4.64.0):
#   * `redeploy` / `restart` only ever act on the LATEST deployment of a service — there is
#     NO CLI flag to redeploy an arbitrary OLDER deployment id. To pin a specific historical
#     deployment you must use the Railway DASHBOARD ("Deployments" tab -> "..." -> "Redeploy"
#     / "Rollback" on the chosen build). This script automates everything the CLI *can* do and
#     prints the exact dashboard fallback for the rest.
#   * `deployment list --json` is the source of truth for deployment ids + statuses. Use it to
#     identify the last SUCCESS prior to the bad deploy.
#   * The ClickHouse persistent volume (/var/lib/clickhouse, 50GB) is NOT touched by a service
#     rollback/redeploy/restart — trace data survives. A rollback only swaps the running image
#     /build; it does NOT wipe the volume. (Only a NEW CH_CLEAR_OPIK_DB token would.)
#
# Safety: this script never sets CH_CLEAR_OPIK_DB and never runs DROP DATABASE. The self-heal
# itself is non-destructive, so "rolling back" the clickhouse build is rarely needed — but if the
# new build is broken at the container/boot level, this reverts the IMAGE while keeping data.
set -uo pipefail

: "${RAILWAY_API_TOKEN:?set RAILWAY_API_TOKEN in your env first}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
BIN="${RAILWAY_BIN:-$REPO_ROOT/tools/railway-cli/railway.exe}"
PROJ="7ccaf972-0b24-46f2-a888-e877cb0cad7c"
ENVN="${ENV_NAME:-production}"
TARGET="${1:-inspect}"

[ -x "$BIN" ] || { echo "CLI not found / not executable at: $BIN"; exit 1; }
die() { echo "FATAL: $*" >&2; exit 1; }

"$BIN" whoami || die "auth failed (check RAILWAY_API_TOKEN)"

list_deploys() {
  local svc="$1"
  echo "------------------------------------------------------------"
  echo ">>> recent deployments for service '$svc' (newest first):"
  echo ">>>   look for the last status=SUCCESS BEFORE the bad one — note its id"
  "$BIN" deployment list -s "$svc" -p "$PROJ" -e "$ENVN" --limit 10 --json \
    || "$BIN" deployment list -s "$svc" -p "$PROJ" -e "$ENVN" --limit 10 \
    || echo "  (could not list deployments for $svc)"
  echo "------------------------------------------------------------"
}

case "$TARGET" in

  inspect)
    list_deploys clickhouse
    list_deploys backend
    echo
    echo ">>> To roll a service back to a SPECIFIC older deployment id, use the dashboard:"
    echo ">>>   Railway -> project opik-amabile -> environment production -> <service>"
    echo ">>>   -> Deployments tab -> pick the last green build -> '...' -> Redeploy/Rollback"
    echo ">>> Or re-run this script with: clickhouse | backend"
    ;;

  clickhouse)
    # CH is a CUSTOM Dockerfile service: a 'rollback' means rebuilding from the PREVIOUS,
    # known-good source. Check out the prior git tag/commit of services/clickhouse, then `up`.
    echo ">>> ClickHouse rollback (custom Dockerfile service)."
    list_deploys clickhouse
    PREV_REF="${PREV_REF:-}"
    if [ -z "$PREV_REF" ]; then
      cat <<'EOF'
>>> No PREV_REF given. Pick the previous known-good ref of services/clickhouse and re-run:
>>>     PREV_REF=<git-tag-or-sha> bash scripts/rollback-fix.sh clickhouse
>>>
>>> FASTEST path (no rebuild, data-safe): use the dashboard to "Redeploy" the last green
>>> clickhouse deployment id shown above. The persistent volume is untouched.
>>>
>>> If git history is available, this script can rebuild the old source instead.
EOF
      exit 0
    fi
    command -v git >/dev/null 2>&1 || die "git not available; use the dashboard redeploy path instead"
    echo ">>> checking out services/clickhouse @ $PREV_REF (worktree-local, non-destructive to current HEAD via stash)"
    git stash push -- services/clickhouse >/dev/null 2>&1 || true
    git checkout "$PREV_REF" -- services/clickhouse \
      || die "could not checkout $PREV_REF for services/clickhouse"
    ( cd "$REPO_ROOT/services/clickhouse" && "$BIN" up --service clickhouse -p "$PROJ" -e "$ENVN" --ci \
        -m "ROLLBACK clickhouse to ${PREV_REF}" ) \
      || die "rollback build FAILED — fall back to dashboard redeploy of last green deployment id"
    echo ">>> restoring working tree (services/clickhouse) to HEAD"
    git checkout HEAD -- services/clickhouse || true
    git stash pop >/dev/null 2>&1 || true
    echo ">>> clickhouse rollback build submitted. Watch logs:"
    echo "    \"$BIN\" logs -s clickhouse -d --lines 80 -p $PROJ -e $ENVN"
    echo ">>> NOTE: persistent volume preserved — no trace data lost."
    ;;

  backend)
    # backend is an IMAGE service (ghcr.io/comet-ml/opik/opik-backend:latest). A bad migration
    # leaves the new deployment crash-looping on /is-alive/ping. Rolling back = returning to the
    # last healthy deployment. The CLI can only redeploy the LATEST, so:
    echo ">>> Backend rollback (image service)."
    list_deploys backend
    echo
    echo ">>> Backend keeps NO local state to lose (state lives in MySQL/ClickHouse/Redis), so the"
    echo ">>> safe move when a migration deploy is wedged is to redeploy the LAST GREEN backend"
    echo ">>> deployment id from the list above — via the DASHBOARD (CLI cannot target an old id):"
    echo ">>>   Railway -> backend -> Deployments -> <last SUCCESS id> -> '...' -> Redeploy"
    echo
    if [ "${ROLLBACK_BACKEND_RESTART:-}" = "1" ]; then
      echo ">>> ROLLBACK_BACKEND_RESTART=1: restarting the latest backend deployment (no rebuild)."
      echo ">>> Use this ONLY if the failure was transient (e.g. CH not yet healthy) and the image"
      echo ">>> itself is fine — the migration will simply be retried against ClickHouse."
      "$BIN" restart -s backend -y -p "$PROJ" -e "$ENVN" \
        || die "backend restart failed; use the dashboard redeploy path"
      echo ">>> backend restart submitted. Watch logs:"
      echo "    \"$BIN\" logs -s backend -d --lines 80 -p $PROJ -e $ENVN"
    else
      echo ">>> (no action taken — re-run with ROLLBACK_BACKEND_RESTART=1 to just restart the latest"
      echo ">>>  deployment, or use the dashboard to pin a specific previous green deployment.)"
    fi
    ;;

  *)
    die "unknown target '$TARGET' — use: inspect | clickhouse | backend"
    ;;
esac

echo ">>> rollback helper done. Re-verify with: bash scripts/verify-fix.sh"
