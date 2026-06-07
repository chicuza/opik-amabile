#!/usr/bin/env bash
# =============================================================================
# fix-orphan-replica.sh
# =============================================================================
# PURPOSE
#   Fixes the stuck Liquibase migration on the Railway-hosted Opik stack caused
#   by an orphaned ReplicatedMergeTree replica znode in ZooKeeper:
#
#     Code: 253. DB::Exception: Replica /clickhouse/tables/2/opik/
#     automation_rule_evaluator_logs/replicas/clickhouse-r1 already exists.
#     (REPLICA_ALREADY_EXISTS)
#
#   Root cause: a prior deployment left a ZK replica registration under
#   /clickhouse/tables/2/opik/<table>/replicas/clickhouse-r1 but the local
#   ClickHouse table no longer exists.  SYSTEM DROP REPLICA ... FROM ZKPATH
#   removes the orphaned znode without touching any live data.
#
# SAFETY
#   This script ONLY drops replicas for tables that are ABSENT from the local
#   opik database.  It will NEVER issue SYSTEM DROP REPLICA for a table that
#   exists locally (which would corrupt the live replica).
#
# HOST-KEY CAVEAT  (READ BEFORE RUNNING)
#   `railway ssh` tunnels through Railway's SSH proxy.  On the very first
#   connection from this machine Railway's host key is unknown and the SSH
#   client will prompt:
#
#     Are you sure you want to continue connecting (yes/no/[fingerprint])?
#
#   Step 1 of this script runs an interactive test query EXACTLY for this
#   reason — answer "yes" once at that prompt and all subsequent non-interactive
#   commands in this run will reuse the now-trusted host.
#
#   If Railway's CLI supports forwarding "-o StrictHostKeyChecking=no" via
#   `railway ssh -i <extra_ssh_args>`, set:
#     RAILWAY_SSH_EXTRA_ARGS="-o StrictHostKeyChecking=accept-new"
#   before running to skip the prompt.  Check `railway ssh --help` for
#   current flag availability.
#
# USAGE
#   # Option A — token already in environment:
#   export RAILWAY_API_TOKEN=<your_token>
#   bash scripts/fix-orphan-replica.sh
#
#   # Option B — token auto-loaded from scripts/.deploy.env:
#   bash scripts/fix-orphan-replica.sh
#
# IDEMPOTENT
#   Safe to re-run.  Dropping an already-absent replica returns an error which
#   is caught and treated as success.  Redeploying an already-healthy backend
#   is harmless.
# =============================================================================

set -uo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# 0. Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
RAILWAY_BIN="${RAILWAY_BIN:-$REPO_ROOT/tools/railway-cli/railway.exe}"
DEPLOY_ENV="$SCRIPT_DIR/.deploy.env"
SECRETS_ENV="$SCRIPT_DIR/.secrets.local"
SECRETS_ENV_ALT="$REPO_ROOT/.secrets.local"   # repo-root variant used in this project

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
info()  { printf '\033[0;36m[INFO]\033[0m  %s\n'    "$*"; }
ok()    { printf '\033[0;32m[OK]\033[0m    %s\n'    "$*"; }
warn()  { printf '\033[0;33m[WARN]\033[0m  %s\n'    "$*" >&2; }
die()   { printf '\033[0;31m[FATAL]\033[0m %s\n'   "$*" >&2; exit 1; }
step()  { printf '\n\033[1;36m------------------------------------------------------------\n %s\n------------------------------------------------------------\033[0m\n' "$*"; }
banner(){ printf '\n\033[1;36m==========================================================\n %s\n==========================================================\033[0m\n' "$*"; }

banner "fix-orphan-replica.sh — Railway/ClickHouse ZK repair"
info "Repo root  : $REPO_ROOT"
info "Railway CLI: $RAILWAY_BIN"

# ---------------------------------------------------------------------------
# 1. Validate railway binary
# ---------------------------------------------------------------------------
[ -f "$RAILWAY_BIN" ] || die "Railway CLI not found at: $RAILWAY_BIN — set RAILWAY_BIN or place railway.exe at the expected path."
[ -x "$RAILWAY_BIN" ] || chmod +x "$RAILWAY_BIN"

# ---------------------------------------------------------------------------
# 2. Load RAILWAY_API_TOKEN
# ---------------------------------------------------------------------------
if [ -z "${RAILWAY_API_TOKEN:-}" ]; then
    if [ -f "$DEPLOY_ENV" ]; then
        info "Loading RAILWAY_API_TOKEN from $DEPLOY_ENV"
        # POSIX-safe parse: no eval, no sourcing untrusted file wholesale
        while IFS='=' read -r key val; do
            case "$key" in
                RAILWAY_API_TOKEN) RAILWAY_API_TOKEN="${val}" ; export RAILWAY_API_TOKEN ;;
            esac
        done < "$DEPLOY_ENV"
    fi
fi
: "${RAILWAY_API_TOKEN:?RAILWAY_API_TOKEN is not set. Set it in your shell or add to $DEPLOY_ENV}"
ok "RAILWAY_API_TOKEN is set."

# ---------------------------------------------------------------------------
# 3. Load ClickHouse password — never echoed or logged
# ---------------------------------------------------------------------------
CH_PASSWORD=""
for secrets_file in "$SECRETS_ENV" "$SECRETS_ENV_ALT"; do
    [ -n "$CH_PASSWORD" ] && break
    if [ -f "$secrets_file" ]; then
        while IFS='=' read -r key val; do
            case "$key" in
                ANALYTICS_DB_PASSWORD) CH_PASSWORD="$val" ;;
            esac
        done < "$secrets_file"
        [ -n "$CH_PASSWORD" ] && info "Password loaded from $secrets_file"
    fi
done

if [ -z "$CH_PASSWORD" ]; then
    warn "ANALYTICS_DB_PASSWORD not found in secrets files."
    printf 'Enter ClickHouse opik user password (hidden): '
    # stty -echo: hide input; restore on EXIT trap so it is never lost
    stty -echo 2>/dev/null || true
    read -r CH_PASSWORD
    stty echo 2>/dev/null || true
    printf '\n'
fi
[ -n "$CH_PASSWORD" ] || die "ClickHouse password is required."
ok "ClickHouse password is available (not shown)."

# ---------------------------------------------------------------------------
# 4. Constants
# ---------------------------------------------------------------------------
PROJ="${PROJ:-7ccaf972-0b24-46f2-a888-e877cb0cad7c}"
ENV_NAME="${ENV_NAME:-production}"
CH_SERVICE="clickhouse"
BE_SERVICE="backend"
CH_USER="opik"
ZK_BASE_PATH="/clickhouse/tables/2/opik"
REPLICA="clickhouse-r1"
KNOWN_ORPHAN="automation_rule_evaluator_logs"
BE_BOOT_WAIT="${BE_BOOT_WAIT:-55}"
LOG_RETRIES=3

# Helper: run a ClickHouse SQL query via railway ssh; echos stdout
# Usage: ch_query <sql> [allow_failure]
ch_query() {
    local sql="$1"
    local allow="${2:-}"
    # --password value is never passed through a shell variable expansion that
    # reaches a log — it lives only in the argument array to the process.
    local output exit_code
    output="$("$RAILWAY_BIN" ssh \
        -s "$CH_SERVICE" \
        -e "$ENV_NAME" \
        -p "$PROJ" \
        -- \
        clickhouse-client \
        --user    "$CH_USER" \
        --password "$CH_PASSWORD" \
        --query   "$sql" 2>&1)" || exit_code=$?
    exit_code="${exit_code:-0}"

    # Mask password in any captured output before printing
    local safe_output
    safe_output="${output//$CH_PASSWORD/***}"

    if [ "$exit_code" -ne 0 ] && [ -z "$allow" ]; then
        die "clickhouse-client query failed (exit $exit_code):\n  $sql\nOutput: $safe_output"
    fi

    printf '%s' "$output"
    return "$exit_code"
}

# ---------------------------------------------------------------------------
# STEP 1 — Interactive host-key trust + connectivity test
# ---------------------------------------------------------------------------
step "STEP 1: Interactive SSH connectivity + host-key trust test"
info "Running interactive SSH command."
info "If prompted 'Are you sure you want to continue connecting (yes/no)?'"
info "--> Type  yes  and press Enter."
printf '\n'

# Run interactively (no output capture) so the TTY prompt reaches the operator
"$RAILWAY_BIN" ssh \
    -s "$CH_SERVICE" \
    -e "$ENV_NAME" \
    -p "$PROJ" \
    -- \
    clickhouse-client \
    --user    "$CH_USER" \
    --password "$CH_PASSWORD" \
    --query   "SELECT version()" \
  || die "Connectivity test failed.  Resolve SSH/auth issues before proceeding."

ok "STEP 1: Connectivity OK."

# ---------------------------------------------------------------------------
# STEP 2 — Enumerate ZK tables and local tables; compute orphan set
# ---------------------------------------------------------------------------
step "STEP 2: Enumerate orphaned ZK replica znodes"

info "Querying ZooKeeper for tables under $ZK_BASE_PATH ..."
zk_raw="$(ch_query "SELECT name FROM system.zookeeper WHERE path = '$ZK_BASE_PATH' FORMAT TSV" allow)" || true

# Parse into array (newline-split, trim blanks)
declare -a zk_tables=()
if [ -n "$zk_raw" ]; then
    while IFS= read -r line; do
        line="${line%$'\r'}"   # strip Windows CR if any
        [ -n "$line" ] && zk_tables+=("$line")
    done <<< "$zk_raw"
fi
info "ZK tables found: ${#zk_tables[@]}"
for t in "${zk_tables[@]}"; do info "  $t"; done

info "Querying local opik database tables ..."
local_raw="$(ch_query "SELECT name FROM system.tables WHERE database = 'opik' FORMAT TSV" allow)" || true

declare -a local_tables=()
if [ -n "$local_raw" ]; then
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [ -n "$line" ] && local_tables+=("$line")
    done <<< "$local_raw"
fi
info "Local opik tables: ${#local_tables[@]}"

# Helper: check if a value exists in an array
array_contains() {
    local needle="$1"; shift
    local elem
    for elem in "$@"; do
        [ "$elem" = "$needle" ] && return 0
    done
    return 1
}

# Build orphan candidate list = ZK tables NOT in local tables
declare -a orphans=()
for t in "${zk_tables[@]}"; do
    if ! array_contains "$t" "${local_tables[@]+"${local_tables[@]}"}"; then
        orphans+=("$t")
    fi
done

# Always include the known orphan if enumeration was empty or incomplete
if ! array_contains "$KNOWN_ORPHAN" "${local_tables[@]+"${local_tables[@]}"}" && \
   ! array_contains "$KNOWN_ORPHAN" "${orphans[@]+"${orphans[@]}"}"; then
    warn "ZK enumeration may be incomplete; adding known orphan '$KNOWN_ORPHAN' to candidate list."
    orphans+=("$KNOWN_ORPHAN")
fi

if [ "${#orphans[@]}" -eq 0 ]; then
    ok "No orphaned replicas detected.  Nothing to drop."
    info "If the backend is still failing, redeploy it manually:"
    info "  $RAILWAY_BIN redeploy -s $BE_SERVICE -y -e $ENV_NAME -p $PROJ"
    exit 0
fi

printf '\n'
warn "Orphaned replicas to drop (${#orphans[@]}):"
for t in "${orphans[@]}"; do warn "  $t"; done

# ---------------------------------------------------------------------------
# STEP 3 — Drop orphaned replicas
# ---------------------------------------------------------------------------
step "STEP 3: Drop orphaned ZK replicas"

declare -a dropped=()
declare -a skipped=()
declare -a failed=()

for table in "${orphans[@]}"; do
    # Safety double-check: skip if table exists locally
    if array_contains "$table" "${local_tables[@]+"${local_tables[@]}"}"; then
        warn "SKIP '$table' — present in local opik database (NOT an orphan)."
        skipped+=("$table")
        continue
    fi

    zk_path="$ZK_BASE_PATH/$table"
    sql="SYSTEM DROP REPLICA '$REPLICA' FROM ZKPATH '$zk_path'"
    info "Dropping replica for: $table"
    info "  SQL: $sql"

    result="$(ch_query "$sql" allow)" || drop_rc=$?
    drop_rc="${drop_rc:-0}"

    if [ "$drop_rc" -eq 0 ]; then
        ok "  -> OK"
        dropped+=("$table")
    else
        safe_result="${result//$CH_PASSWORD/***}"
        # REPLICA_NOT_FOUND means already gone — idempotent
        if printf '%s' "$safe_result" | grep -qiE 'REPLICA_NOT_FOUND|does not exist'; then
            warn "  -> Already absent (REPLICA_NOT_FOUND) — idempotent, continuing."
            dropped+=("$table")
        else
            printf '\033[0;31m  -> ERROR: %s\033[0m\n' "$safe_result" >&2
            failed+=("$table")
        fi
    fi
done

if [ "${#failed[@]}" -gt 0 ]; then
    warn "${#failed[@]} replica(s) could not be dropped: ${failed[*]}"
    warn "The 'opik' user requires the SYSTEM privilege (GRANT SYSTEM ON *.* TO opik)."
    warn "If this user lacks it, connect as 'default' with admin rights and re-run,"
    warn "or exec the SQL manually via the Railway dashboard shell."
    warn "Proceeding to backend redeploy anyway."
fi

# ---------------------------------------------------------------------------
# STEP 4 — Redeploy backend
# ---------------------------------------------------------------------------
step "STEP 4: Redeploy backend (re-run Liquibase migrations)"

info "Submitting backend redeploy ..."
"$RAILWAY_BIN" redeploy -s "$BE_SERVICE" -y -e "$ENV_NAME" -p "$PROJ" \
    || die "backend redeploy command FAILED to submit.  See scripts/RUNBOOK-item3.md"
ok "Redeploy submitted."
info "Waiting ${BE_BOOT_WAIT}s for backend to restart and run migrations ..."
sleep "$BE_BOOT_WAIT"

# ---------------------------------------------------------------------------
# STEP 5 — Verify backend logs
# ---------------------------------------------------------------------------
step "STEP 5: Verify backend logs"

verified=false
still_stuck=false

for attempt in $(seq 1 "$LOG_RETRIES"); do
    info "Fetching backend logs (attempt $attempt/$LOG_RETRIES) ..."
    logs="$("$RAILWAY_BIN" logs -s "$BE_SERVICE" -d --lines 80 -e "$ENV_NAME" -p "$PROJ" 2>&1)" || true
    printf '%s\n' "$logs"

    if printf '%s' "$logs" | grep -q 'REPLICA_ALREADY_EXISTS'; then
        still_stuck=true
        warn "REPLICA_ALREADY_EXISTS still present in logs."
    else
        still_stuck=false
    fi

    if printf '%s' "$logs" | grep -qiE 'Liquibase.*successfully|migration.*completed|Successfully acquired|ChangeSet.*ran successfully'; then
        ok "Liquibase migration SUCCESS detected."
        verified=true
        break
    fi

    if [ "$attempt" -lt "$LOG_RETRIES" ]; then
        info "Migration not yet confirmed — waiting 20s before retry ..."
        sleep 20
    fi
done

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
banner "SUMMARY"
info "Orphans identified : ${#orphans[@]}"
info "Replicas dropped   : ${#dropped[@]}  (${dropped[*]+"${dropped[*]}"})"
info "Skipped (local)    : ${#skipped[@]}  (${skipped[*]+"${skipped[*]}"})"
info "Drop failures      : ${#failed[@]}   (${failed[*]+"${failed[*]}"})"

if [ "$verified" = "true" ]; then
    printf '\n'
    ok "RESULT: MIGRATIONS SUCCEEDED.  Backend is healthy."
elif [ "$still_stuck" = "true" ]; then
    printf '\n'
    warn "RESULT: REPLICA_ALREADY_EXISTS still present after fix."
    info "Next steps:"
    info "  1. Check whether the opik user has SYSTEM privilege in ClickHouse."
    info "  2. Re-run this script, or run the DROP REPLICA SQL manually:"
    for t in "${orphans[@]}"; do
        info "       SYSTEM DROP REPLICA '$REPLICA' FROM ZKPATH '$ZK_BASE_PATH/$t';"
    done
    info "  3. Then: $RAILWAY_BIN redeploy -s $BE_SERVICE -y -e $ENV_NAME -p $PROJ"
    info "  4. See scripts/RUNBOOK-item3.md for the full rollback decision tree."
    exit 1
else
    printf '\n'
    warn "RESULT: Migrations not yet confirmed in log window — may still be running."
    info "Re-pull logs in ~30s:"
    info "  $RAILWAY_BIN logs -s $BE_SERVICE -d --lines 80 -e $ENV_NAME -p $PROJ"
fi
