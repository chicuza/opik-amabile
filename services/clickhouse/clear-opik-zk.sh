#!/bin/sh
# ClickHouse boot helper for the Opik schema on Railway.
#
# Runs in the background (launched by the Dockerfile ENTRYPOINT, after the server)
# on EVERY boot:
#   1. Waits for ClickHouse HTTP to answer.
#   2. ALWAYS (non-destructive) self-heal: reclaims ORPHANED ReplicatedMergeTree
#      replica registrations left in ZooKeeper after a non-graceful redeploy. This
#      is what prevents the Liquibase migration from failing with
#      `REPLICA_ALREADY_EXISTS (253)`. It only drops a replica for a table that does
#      NOT exist locally, so an ACTIVE replica (live table) is never touched.
#
# Optional, flag-gated:
#   CH_FIX_OPIK_USER=1        -> recreate the `opik` admin user from $CLICKHOUSE_PASSWORD
#                                (safe, no data loss).
#   CH_CLEAR_OPIK_DB=<token>  -> DESTRUCTIVE one-shot: drop the whole `opik` DB + the
#                                Liquibase changelog + all opik replica znodes so the
#                                schema rebuilds from scratch. Runs ONCE per distinct
#                                token, recorded in a sentinel on the persistent volume;
#                                leaving the variable set across redeploys is a no-op
#                                (to wipe again, set a NEW token value).
#
# Secrets are read from the environment ($CLICKHOUSE_PASSWORD); never hardcoded or logged.
set -u

CH_USER="${CLICKHOUSE_USER:-opik}"
SENTINEL="/var/lib/clickhouse/.opik-cleared"

if [ -z "${CLICKHOUSE_PASSWORD:-}" ]; then
  echo "[clear-opik-zk] CLICKHOUSE_PASSWORD not set — cannot authenticate; skipping."
  exit 0
fi

echo "[clear-opik-zk] BOOT — CH_FIX_OPIK_USER='${CH_FIX_OPIK_USER:-}' CH_CLEAR_OPIK_DB='${CH_CLEAR_OPIK_DB:+<set>}'"

# ---- wait for ClickHouse HTTP ------------------------------------------------
echo "[clear-opik-zk] waiting for ClickHouse HTTP..."
ready=0
for i in $(seq 1 120); do
  if wget -qO- --timeout=2 http://127.0.0.1:8123/ping 2>/dev/null | grep -q "Ok"; then
    echo "[clear-opik-zk] CH ready (after ${i}*2s)"; ready=1; break
  fi
  sleep 2
done
[ "$ready" = "1" ] || { echo "[clear-opik-zk] CH never became ready; skipping."; exit 0; }

# ---- helpers (password from env; never echoed) -------------------------------
# Diagnostic/DDL as the local `default` user (no_password on 127.0.0.1).
q() {
  wget -qO- --post-data="$1" "http://127.0.0.1:8123/?database=default" 2>&1 | head -3
}
# Admin query authenticated as the opik user.
qadmin() {
  wget -qO- --user="$CH_USER" --password="$CLICKHOUSE_PASSWORD" \
    --post-data="$1" "http://127.0.0.1:8123/?database=default" 2>&1 | head -3
}
# Single scalar value as the opik user.
scalar() {
  wget -qO- --user="$CH_USER" --password="$CLICKHOUSE_PASSWORD" \
    --post-data="$1" "http://127.0.0.1:8123/" 2>/dev/null | tr -d '\r\n'
}

# Opik ReplicatedMergeTree tables (zk path = /clickhouse/tables/<shard>/opik/<table>).
OPIK_TABLES="traces spans feedback_scores feedback_scores_by_id experiments \
experiment_items dataset_items datasets attachments authored_feedback_scores \
automation_rule_evaluator_logs guardrails llm_provider_api_key_definition \
prompt_versions prompts usage workspace_configurations workspace_metadata"

# ---- optional: recreate opik admin user (flag-gated, no data loss) -----------
if [ "${CH_FIX_OPIK_USER:-}" = "1" ]; then
  echo "[clear-opik-zk] CH_FIX_OPIK_USER=1 — recreating opik user from env (password not logged)"
  q "DROP USER IF EXISTS opik" >/dev/null
  q "CREATE USER opik IDENTIFIED WITH plaintext_password BY '${CLICKHOUSE_PASSWORD}' HOST ANY" >/dev/null
  q "GRANT ALL ON *.* TO opik WITH GRANT OPTION" >/dev/null
  echo "[clear-opik-zk] opik user recreated"
fi

# ---- ALWAYS: non-destructive orphan-replica self-heal ------------------------
SHARD="$(scalar "SELECT getMacro('shard')")"
REPLICA="$(scalar "SELECT getMacro('replica')")"
if [ -n "$SHARD" ] && [ -n "$REPLICA" ]; then
  echo "[clear-opik-zk] self-heal: shard='${SHARD}' replica='${REPLICA}'"
  BASE="/clickhouse/tables/${SHARD}/opik"
  # Dynamically enumerate EVERY table znode under the opik ZK path. This catches
  # staging/swap tables (e.g. automation_rule_evaluator_logs1) and any future tables
  # not in the static list. Falls back to the static list if system.zookeeper is
  # unavailable or the path does not exist yet.
  ZK_TABLES="$(scalar "SELECT arrayStringConcat(groupArray(name), ' ') FROM system.zookeeper WHERE path = '${BASE}'")"
  case "$ZK_TABLES" in *xception*|*Exception*) ZK_TABLES="" ;; esac
  CANDIDATES="$(printf '%s %s' "$OPIK_TABLES" "$ZK_TABLES" | tr ' ' '\n' | sed '/^$/d' | sort -u)"
  for tbl in $CANDIDATES; do
    exists="$(scalar "SELECT count() FROM system.tables WHERE database='opik' AND name='${tbl}'")"
    if [ "$exists" = "0" ]; then
      # Local table absent: reclaim any stale replica znode left in ZooKeeper.
      # CH refuses to drop an ACTIVE replica, so live tables are never affected.
      out="$(qadmin "SYSTEM DROP REPLICA '${REPLICA}' FROM ZKPATH '${BASE}/${tbl}'")"
      case "$out" in
        *xception*|*Exception*) : ;;  # path absent / nothing to reclaim — ignore
        *) echo "[clear-opik-zk]   reclaimed orphan replica for opik.${tbl}" ;;
      esac
    fi
  done
else
  echo "[clear-opik-zk] WARN: could not resolve {shard}/{replica} macros — skipping self-heal"
fi

# ---- optional DESTRUCTIVE one-shot: full opik wipe (token-gated sentinel) ----
CLEAR_TOKEN="${CH_CLEAR_OPIK_DB:-}"
if [ -n "$CLEAR_TOKEN" ] && [ "$CLEAR_TOKEN" != "0" ]; then
  prev=""
  [ -f "$SENTINEL" ] && prev="$(tr -d '\r\n' < "$SENTINEL" 2>/dev/null)"
  if [ "$CLEAR_TOKEN" = "$prev" ]; then
    echo "[clear-opik-zk] CH_CLEAR_OPIK_DB token already applied (sentinel present) — skipping destructive wipe"
  else
    echo "[clear-opik-zk] === DESTRUCTIVE WIPE (new token) ==="
    qadmin "DROP DATABASE IF EXISTS opik SYNC" >/dev/null
    qadmin "DROP TABLE IF EXISTS default.DATABASECHANGELOG SYNC" >/dev/null
    qadmin "DROP TABLE IF EXISTS default.DATABASECHANGELOGLOCK SYNC" >/dev/null
    if [ -n "$SHARD" ] && [ -n "$REPLICA" ]; then
      for tbl in $OPIK_TABLES; do
        qadmin "SYSTEM DROP REPLICA '${REPLICA}' FROM ZKPATH '/clickhouse/tables/${SHARD}/opik/${tbl}'" >/dev/null 2>&1 || true
      done
    fi
    if printf '%s' "$CLEAR_TOKEN" > "$SENTINEL" 2>/dev/null; then
      echo "[clear-opik-zk] wipe complete; sentinel recorded. To wipe again, set CH_CLEAR_OPIK_DB to a NEW value."
    else
      echo "[clear-opik-zk] WARN: wipe done but could not write sentinel ${SENTINEL} (may re-wipe next boot)"
    fi
  fi
fi

echo "[clear-opik-zk] done."
