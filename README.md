# AmabileAI Observability — Railway deployment

Infrastructure-as-config for deploying the **AmabileAI Observability Platform** (LLM observability + guardrails) on Railway, exposed at `https://fabricaai.amabileai.com.br`.

## Architecture

9 Railway services:

| # | Service | Image / Source | Purpose |
|---|---|---|---|
| 1 | `mysql` | Railway MySQL template | State DB (Liquibase migrations) |
| 2 | `redis` | Railway Redis template | Cache + queues |
| 3 | `zookeeper` | `zookeeper:3.9.4` | ClickHouse Keeper coordination |
| 4 | `clickhouse` | custom (Dockerfile in `services/clickhouse/`) | Analytics DB for traces |
| 5 | `minio` | `bitnamilegacy/minio:2025.7.23-debian-12-r5` | S3-compat blob storage |
| 6 | `backend` | upstream backend image | Core Java REST API |
| 7 | `python-backend` | upstream python-backend image | LLM-as-judge + code executor (subprocess strategy) |
| 8 | `guardrails` | upstream guardrails image | PII + topic classification |
| 9 | `frontend` | custom (overlay on upstream frontend with AmabileAI brand + Railway-internal nginx) | UI + reverse-proxy → public domain |

> Upstream image registry references are kept inside `services/*/railway.json` for operational reproducibility. The user-facing UI is fully rebranded to AmabileAI via the nginx overlay in `services/frontend/`.

## Auth / API gateway

Authentication and API-gateway concerns are **not** handled inside this project. They are owned by the
shared **Tyk API Gateway** (`https://api.amabileai.com.br`, separate Railway project), which fronts
Amabile AI services with JWT auth, rate limiting and quotas. A previous in-repo `keycloak` + `oauth2-proxy`
SSO scaffold was removed (it was orphaned — never wired into `bootstrap.sh`/`set-env.sh` and not deployable);
route the Opik/`fabricaai` stack through Tyk instead. See the Notion page "🛡️ Tyk API Gateway — Amabile AI".

## Bring-up

```bash
export RAILWAY_TOKEN=<from-notion-railway-claude-poc>
export CLOUDFLARE_API_TOKEN=<from-notion-cloudflare-claude1>

./scripts/bootstrap.sh        # railway login + project + add services + volumes
./scripts/set-env.sh          # railway variables --set per service
# Wait for all services to deploy (~10-15 min, guardrails downloads HF models on first request)
./scripts/cloudflare-dns.sh   # create proxied CNAME fabricaai → <railway-cname>
./scripts/verify.sh           # health probes
```

After verify is green:

1. Open `https://fabricaai.amabileai.com.br/` → sign up first admin.
2. UI → Account → API keys → generate.
3. Save key to Notion under "AmabileAI — API keys".
4. Test SDK:

```bash
export OPIK_URL_OVERRIDE=https://fabricaai.amabileai.com.br/api
export OPIK_API_KEY=<key>
export OPIK_WORKSPACE=default
python sdk-examples/python_smoke.py
```

> `OPIK_*` environment variables are SDK contract names (the SDK package is `opik` on PyPI). They are kept verbatim because renaming them would break the SDK; only the user-facing UI is rebranded.

## Credentials

Loaded from env vars at runtime — **never** committed.

| Var | Source |
|---|---|
| `RAILWAY_TOKEN` | Notion page `94dfd4f3-da6b-4fa2-a0f0-202180889773` (token `claude-poc`) |
| `CLOUDFLARE_API_TOKEN` | Notion page `38ecb43f-c515-4c75-82d1-cc01c2463493` (token `claude1`) |
| `CLOUDFLARE_ACCOUNT_ID` | `a6198bf88ab2f420eb3bcf23c2225a8b` |

## Operational notes

- **`python-backend`** runs `PYTHON_CODE_EXECUTOR_STRATEGY=process` (Railway forbids privileged Docker-in-Docker).
- **`guardrails`** needs ~8 GB RAM and downloads ~2-3 GB of HuggingFace models on first request; cache persists on the volume at `/root/.cache/huggingface`.
- **Cloudflare proxy** is enabled (orange-cloud); zone SSL mode must be **Full (strict)**.
- **Frontend brand overlay** lives in `services/frontend/assets/` (`brand.css`, `brand-cleanup.js`, AmabileAI logo and favicon set) and is wired into `services/frontend/default.conf` via `sub_filter` + asset routes.

## Brand overlay

The frontend service rebrands the upstream Opik UI to AmabileAI without forking:

- `services/frontend/default.conf` — `sub_filter` rewrites of `<title>` and favicon, plus injection of `<link rel="stylesheet" href="/amabile/brand.css">` and `<script src="/amabile/brand-cleanup.js" defer>`.
- `services/frontend/assets/brand.css` — AmabileAI design tokens (palette extracted from the official brand guide), surface/text/component overrides.
- `services/frontend/assets/brand-cleanup.js` — DOM `MutationObserver` that replaces user-facing strings ("Opik" → "AmabileAI", etc.), removes external comet/github-comet-ml/social links, and swaps any upstream logo image for the AmabileAI logo.
- `services/frontend/assets/amabile-logo-*.png` + `favicon.ico` + `manifest.webmanifest` — multi-size brand assets.

## References

- Railway docs: <https://docs.railway.com/>
- Railway config-as-code: <https://docs.railway.com/reference/config-as-code>
- Plan file: `C:\Users\chicu\.claude\plans\cryptic-drifting-russell.md`
