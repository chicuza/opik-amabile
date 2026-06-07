# RUNBOOK — Item 3: ClickHouse `REPLICA_ALREADY_EXISTS` self-heal deploy

**Stack:** AmabileAI Observability (Opik fork) on Railway
**Public UI:** https://fabricaai.amabileai.com.br
**Project:** `opik-amabile` (`7ccaf972-0b24-46f2-a888-e877cb0cad7c`) · env `production` (`88dc2fd7-cea1-4e01-86ac-07cf7d6d39ac`)
**CLI:** `./tools/railway-cli/railway.exe` (v4.64.0) · auth via `RAILWAY_API_TOKEN` (account token)

---

## What this deploy does

Backend Liquibase migration was failing with ClickHouse `REPLICA_ALREADY_EXISTS (253)` — an
orphaned ZooKeeper replica znode left behind by a non-graceful redeploy. The fix is an
**always-on, NON-destructive** self-heal in `services/clickhouse/clear-opik-zk.sh`: on every boot
it runs `SYSTEM DROP REPLICA … FROM ZKPATH` **only for opik tables that are ABSENT locally**
(orphan znodes). ClickHouse refuses to drop an ACTIVE replica, so live tables are never touched.
The destructive `DROP DATABASE` path stays gated behind a `CH_CLEAR_OPIK_DB` token + a sentinel
file on the persistent volume — it is NOT triggered by this deploy.

Order matters: rebuild **clickhouse** first (so the self-heal clears the orphan), confirm it is
healthy, then redeploy **backend** so Liquibase re-runs against the cleaned ClickHouse.

---

## RUN IT (PowerShell, operator runs these with the `!` prefix)

Set the token in your shell, then run the deploy script via bash:

```
!$env:RAILWAY_API_TOKEN = "<account token>"; bash scripts/deploy-fix.sh 2>&1 | Tee-Object -FilePath "$env:TEMP\opik-deploy.log"
```

The script pauses after the ClickHouse logs (step 3) and asks you to confirm CH is healthy
before it redeploys backend. To skip the prompt in an unattended run, set `CONFIRM_CH_HEALTHY=1`
(only do this if you trust CH came up clean):

```
!$env:RAILWAY_API_TOKEN = "<token>"; $env:CONFIRM_CH_HEALTHY = "1"; bash scripts/deploy-fix.sh
```

Then verify:

```
!$env:RAILWAY_API_TOKEN = "<token>"; bash scripts/verify-fix.sh
```

(`verify-fix.sh` also runs the public HTTPS probes; the log greps are skipped if the token is unset.)

---

## What SUCCESS looks like, per step

| Step | Command | Success signal |
|------|---------|----------------|
| 0 | `whoami` + `link` | prints your account; link may warn (harmless — every call passes `-p/-e/-s`). |
| 1 | baseline backend logs | EXPECTED to still show `REPLICA_ALREADY_EXISTS` (this is the pre-fix state). |
| 2 | `up --service clickhouse --ci` | build streams, ends with a successful build + deploy; **exit code 0**. If it fails, the script ABORTS and does NOT touch backend. |
| 3 | clickhouse runtime logs | `[clear-opik-zk] CH ready`, `[clear-opik-zk] self-heal: shard=… replica=…`, optionally `reclaimed orphan replica for opik.<table>`, then `[clear-opik-zk] done.` CH server answering on 8123. |
| 4 | `redeploy -s backend -y` | redeploy submitted (command exits 0). |
| 5 | backend deploy logs | **NO** `REPLICA_ALREADY_EXISTS`; Liquibase changesets run successfully; app starts and `/is-alive/ping` healthcheck passes. |
| verify | `verify-fix.sh` | `/health`=200, `/guardrails/healthcheck`=200, `/api/v1/private/projects`=401/403 (NOT 500), backend logs free of `REPLICA_ALREADY_EXISTS`. `RESULT: fail=0`. |

---

## FAILURE → ROLLBACK decision tree

First, always inspect deployment state:

```
!$env:RAILWAY_API_TOKEN = "<token>"; bash scripts/rollback-fix.sh inspect
```

```
Step 2 (clickhouse build) FAILS?
  └─ deploy-fix.sh already ABORTED before touching backend. Backend still runs the old image.
     → If CH is now crash-looping on the new build, roll the CH build back:
         PREV_REF=<last-good-git-ref> bash scripts/rollback-fix.sh clickhouse
       (or, fastest + data-safe: dashboard → clickhouse → Deployments → last green id → Redeploy)
     → The persistent volume (/var/lib/clickhouse) is NOT touched — no trace data lost.

Step 3 — CH never logs "[clear-opik-zk] done." / 8123 not answering?
  → DO NOT confirm the prompt. Answer anything other than "yes" (script aborts before backend).
  → Re-pull CH logs; if the container is wedged, treat as a Step-2 failure and roll CH back.

Step 5 — backend STILL shows REPLICA_ALREADY_EXISTS, or healthcheck never goes green?
  ├─ Cause A: backend was redeployed BEFORE CH finished the self-heal (the residual race).
  │    → Just retry the backend deployment now that CH is healthy:
  │        ROLLBACK_BACKEND_RESTART=1 bash scripts/rollback-fix.sh backend
  │      (restart re-runs the migration against the cleaned ClickHouse — no image change.)
  ├─ Cause B: the new backend image itself is bad / migration genuinely broken.
  │    → Roll backend to the last green deployment via the DASHBOARD:
  │        Railway → backend → Deployments → <last SUCCESS id> → "…" → Redeploy
  │      (The CLI's redeploy/restart only act on the LATEST deployment — it cannot target an
  │       arbitrary older id, so the dashboard is required to pin a specific previous build.)
  └─ Backend holds no local state (state is in MySQL/ClickHouse/Redis), so rolling it back is safe.

verify-fix.sh reports /api/v1/private/projects = 500/502/503?
  → Schema still not migrated. Re-pull backend logs (--lines 400), then apply Cause A or B above.
```

### Last-resort destructive reset (NOT part of this deploy)
Only if the schema is unrecoverable: set a **new** `CH_CLEAR_OPIK_DB` token on the clickhouse
service and redeploy it. This drops the whole `opik` DB + Liquibase changelog + opik replica
znodes so the schema rebuilds from scratch — **this WIPES trace data**. Runs once per distinct
token (sentinel on the volume). Do not use unless you accept data loss.

---

## Residual race note (important)

Railway has **no cross-service `dependsOn`** — nothing forces backend to wait for clickhouse to be
healthy. The self-heal must have COMPLETED before backend re-runs Liquibase, otherwise the orphan
znode is still present and the migration fails again (Cause A above). That is exactly why
`deploy-fix.sh`:
1. deploys clickhouse first and aborts the whole run if its build fails, and
2. **pauses for explicit confirmation** (or `CONFIRM_CH_HEALTHY=1`) after showing the CH self-heal
   logs, before redeploying backend.

ClickHouse's `railway.json` uses `overlapSeconds=0` / `drainingSeconds=0` and `restartPolicy
ON_FAILURE/5`, so the old container is gone before the new one starts (clean replica re-registration),
and a transient boot failure self-restarts up to 5 times.

---

## Known latent risk (B2) — flag for follow-up, NOT fixed here

The self-heal iterates a fixed `OPIK_TABLES` list and reclaims orphan znodes per
`/clickhouse/tables/{shard}/opik/<table>`. Opik also creates **staging/swap tables** during some
migrations — e.g. `automation_rule_evaluator_logs1` — which can share (or collide with) the ZK path
of the base table `automation_rule_evaluator_logs`. Because the staging name is not in `OPIK_TABLES`,
a stale `…_logs1` replica znode would NOT be reclaimed by the current self-heal, and could re-trigger
`REPLICA_ALREADY_EXISTS` on a future migration that re-creates that staging table. Mitigation options
(for a follow-up PR, not this deploy): add the known staging-table names to `OPIK_TABLES`, or enumerate
orphan znodes under `/clickhouse/tables/{shard}/opik/` directly instead of using a static list. No
action needed for the current fix, but watch step-5 logs for `…_logs1` if the error recurs.

---

## Files

- `scripts/deploy-fix.sh` — apply the self-heal: CH rebuild → confirm healthy → backend redeploy.
- `scripts/rollback-fix.sh` — `inspect` | `clickhouse` | `backend` rollback helper.
- `scripts/verify-fix.sh` — public HTTPS probes + backend log greps.
- `services/clickhouse/clear-opik-zk.sh` — the always-on non-destructive self-heal.
- `services/clickhouse/railway.json` — DOCKERFILE builder, overlap/drain=0, ON_FAILURE/5.
- `services/backend/railway.json` — IMAGE service, healthcheck `/is-alive/ping`.
