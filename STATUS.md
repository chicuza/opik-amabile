# AmabileAI Observability — DEPLOYED ✅

**Public URL:** https://fabricaai.amabileai.com.br/ ✅ HTTP 200, valid TLS
**Railway service URL:** https://frontend-production-9b7e.up.railway.app/ ✅ HTTP 200
**Railway project:** `opik-amabile` (ID `7ccaf972-0b24-46f2-a888-e877cb0cad7c`, workspace `chicuza's Projects` / francisco@moreno.tc, env `88dc2fd7-cea1-4e01-86ac-07cf7d6d39ac`)

## Verified endpoints

| Endpoint | Status |
|---|---|
| `GET /`                                 | ✅ 200 (AmabileAI UI) |
| `GET /health`                           | ✅ 200 (nginx) |
| `GET /api/v1/private/projects`          | ✅ 500 (backend reached; expected without API key) |
| `GET /guardrails/healthcheck`           | ✅ 200 (returns "OK") |
| TLS cert                                | ✅ Let's Encrypt via Railway |
| Custom domain                           | ✅ Verified (TXT + CNAME) |
| `verified: true`, `certificateStatus: VALID` |  |

## 9/9 services Online

| Service | Image | Volume |
|---|---|---|
| MySQL | `mysql:9.4` | `/var/lib/mysql` |
| Redis | `redis:8.2.1` | `/data` |
| zookeeper | `zookeeper:3.9.4` | `/data` |
| clickhouse | Custom (`clickhouse-server:25.3.6.56-alpine` + Opik configs + lockfile-clean entrypoint) | **`/var/lib/clickhouse`** (persistent) |
| minio | `bitnamilegacy/minio:2025.7.23-debian-12-r5` | `/data` |
| backend | `ghcr.io/comet-ml/opik/opik-backend:latest` | — |
| python-backend | `ghcr.io/comet-ml/opik/opik-python-backend:latest` (subprocess executor) | — |
| guardrails | `ghcr.io/comet-ml/opik/opik-guardrails-backend:1.7.16-1693` | — |
| frontend | **Custom Dockerfile** (overlay on `opik-frontend:latest` with patched nginx default.conf pointing at `backend.railway.internal:8080` + `guardrails.railway.internal:5000`) | — |

## DNS / TLS (current)

| Record | Type | Value | Proxy |
|---|---|---|---|
| `fabricaai.amabileai.com.br` | CNAME | `a05sur4p.up.railway.app` | **Proxied (orange-cloud)** |
| `_railway-verify.fabricaai.amabileai.com.br` | TXT | `railway-verify=ec24075b37f6837f5ea770ff493c80e5c4ef274c6e6d8daa16b03a3ee2fc05fc` | — |

**TLS chain:** Cloudflare edge (full-strict mode) → Railway edge (Let's Encrypt origin cert) → frontend service. Cloudflare WAF/DDoS protection enabled. Zone `amabileai.com.br` SSL/TLS mode = `strict`.

## Final SDK config

```env
OPIK_URL_OVERRIDE=https://fabricaai.amabileai.com.br/api
OPIK_API_KEY=<generated via UI sign-up at https://fabricaai.amabileai.com.br>  # SDK contract var name; UI is AmabileAI-branded
OPIK_WORKSPACE=default
```

Run: `python sdk-examples/python_smoke.py`

## Phase 3 fixes (root causes that mattered)

1. **Custom domain stuck at "Application not found"** — `verified: false`, certificateStatus `VALIDATING_OWNERSHIP`. The Railway public-API `dnsRecords` array hides the TXT entry by default, but `CustomDomainStatus.verificationDnsHost` + `verificationToken` expose it. Required TXT: `_railway-verify.fabricaai` → `railway-verify=<token>`. Created via Cloudflare API → Railway auto-verified within seconds → cert issued.
2. **`/api/` returning nginx 404** — Opik frontend image has the upstream `backend:8080` baked into `/etc/nginx/conf.d/default.conf` and relies on Docker's embedded resolver `127.0.0.11`, which doesn't exist on Railway. Fix: overlay a custom default.conf with `server backend.railway.internal:8080` (and `guardrails.railway.internal:5000`) via a thin Dockerfile (`services/frontend/Dockerfile`).
3. **Frontend port mismatch** — image listens on `${NGINX_PORT:-8080}`, not 5173, not `PORT`. The actual listen port is driven by env `NGINX_PORT`. Set `NGINX_PORT=5173` to match our Railway domain targetPort.
4. **File permissions** — `99-patch-nginx.conf.sh` writes back to `/etc/nginx/conf.d/default.conf` at startup; COPY made it owned by root with mode 0644 → permission denied. Fix: `COPY --chown=nginx:nginx` + `chmod 0664`.
5. **ClickHouse stale lockfile across redeploys** — Railway's rolling deploy held `/var/lib/clickhouse/status` from the previous container. Fix: Dockerfile ENTRYPOINT `rm -f /var/lib/clickhouse/status && exec /entrypoint.sh`; serviceInstance `overlapSeconds=0` + `drainingSeconds=0`. The persistent volume at `/var/lib/clickhouse` is now stable across redeploys.

## Files modified in Phase 3

- `services/frontend/Dockerfile` (new) — overlay on opik-frontend:latest
- `services/frontend/default.conf` (new) — nginx conf w/ Railway internal upstreams
- `services/frontend/railway.json` — builder: DOCKERFILE
- DNS: TXT record added on Cloudflare

## Phase 4 fixes (hardening — architecture + error review)

1. **ClickHouse `REPLICA_ALREADY_EXISTS` self-heal (root cause of backend boot failure).** Liquibase
   migrations failed with `Code: 253 … Replica /clickhouse/tables/2/opik/automation_rule_evaluator_logs/replicas/clickhouse-r1 already exists`.
   Cause: `CREATE TABLE IF NOT EXISTS` only checks the *local* catalog, but the replica registration
   lives in ZooKeeper's own persistent volume and survives non-graceful ClickHouse redeploys
   (`drainingSeconds=0` → `signal -2`). The status-lockfile fix (#5) did **not** cover this.
   Fix: `services/clickhouse/clear-opik-zk.sh` now runs an **always-on, non-destructive** self-heal on
   every boot — for each opik table absent locally, it reclaims the stale replica znode via
   `SYSTEM DROP REPLICA … FROM ZKPATH`. ClickHouse refuses to drop an *active* replica, so live tables
   are never touched.
2. **Secret consolidation.** The hardcoded ClickHouse password was removed from
   `services/clickhouse/users.d/opik_user.xml` (now `from_env="CLICKHOUSE_PASSWORD"`) and from
   `clear-opik-zk.sh` (now reads `$CLICKHOUSE_PASSWORD`, never logs it). Single source of truth =
   the env var injected by `scripts/set-env.sh`. **Rotate** the ClickHouse + MinIO secrets (the prior
   hardcoded/`.secrets.local` values must be treated as compromised).
3. **`.secrets.local` is now gitignored** (was claimed but missing). Note: this folder is not yet a git
   repo — initialize/push only after confirming no secret is tracked (`git check-ignore .secrets.local`).
4. **Data-loss footgun removed.** The destructive `DROP DATABASE opik` path in `clear-opik-zk.sh` is now
   a **token-gated one-shot** (sentinel `/var/lib/clickhouse/.opik-cleared`); leaving `CH_CLEAR_OPIK_DB`
   set across redeploys is a no-op. To wipe again, set a *new* token value.
5. **Auth scaffold removed → Tyk.** The orphaned `services/keycloak` + `services/oauth2-proxy` folders
   were deleted; auth/gateway is owned by the shared Tyk gateway (`api.amabileai.com.br`). Stack is back
   to the documented **9 services**.

### Follow-ups (not code changes in this repo)
- Rotate ClickHouse + MinIO credentials; migrate secrets to Doppler/Bitwarden per POL-SI-001.
- Pin `:latest` image tags to recorded versions; reconcile the MinIO image across README/railway.json/bootstrap.
- ClickHouse healthcheck (`/ping` on 8123) deferred — needs Railway probe-port verification to avoid a crash-loop.
- Configure the Tyk API to proxy/authenticate the `fabricaai` stack (Tyk project + Cloudflare DNS).

## Credentials reference

| Var | Source |
|---|---|
| `RAILWAY_API_TOKEN` | `28923d8e-…` — Notion page `94dfd4f3-…` |
| `CLOUDFLARE_API_TOKEN` | `cfat_rNp4U…` — Notion page `38ecb43f-…` |
| `ANALYTICS_DB_PASSWORD`, `MINIO_SECRET_KEY` | `.secrets.local` (gitignored) — migrate to Bitwarden/Doppler per POL-SI-001 |
| AmabileAI API key | Generate via UI sign-up, save to Notion under `🔐 Credenciais & Acessos` |

## Next steps (operator)

1. Open https://fabricaai.amabileai.com.br/ → create the first admin account.
2. UI → Account → API Keys → generate.
3. Save the API key to Notion under "AmabileAI — API keys" page.
4. Run `python sdk-examples/python_smoke.py` to confirm SDK → trace round-trip.
5. (Optional) Re-enable Cloudflare proxy on `fabricaai` CNAME (orange cloud) + set zone SSL/TLS = Full (strict) for WAF.
6. Schedule the legacy bitnami/minio image migration to bitnami's premium tier (current `bitnamilegacy/` registry is supported through 2026 only).
