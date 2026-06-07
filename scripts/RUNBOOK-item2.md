# RUNBOOK — Item 2: Route the AmabileAI Observability (Opik) stack via Tyk + Cloudflare DNS

**Status:** execution-ready. ADDITIVE and non-destructive. Nothing here removes the existing direct
route `fabricaai.amabileai.com.br -> a05sur4p.up.railway.app`.

**Artifacts:**
- `services/tyk/opik-observability-api.json` — Tyk API definition payload
- `scripts/item2-tyk-cloudflare.sh` — the executor (no secrets; reads env)
- this runbook

---

## 1. Design choice (and why)

**Chosen: path-based additive route on the existing gateway + keyless at Tyk.**

- New API on the **existing** public gateway: `https://api.amabileai.com.br/observability/`
  (Tyk `listen_path = /observability/`, `strip_listen_path = true`).
- `target_url = https://frontend-production-9b7e.up.railway.app/` — the Opik **frontend** nginx,
  which already reverse-proxies `/api/ -> backend.railway.internal:8080` and
  `/guardrails/ -> guardrails.railway.internal:5000`. Pointing Tyk at the frontend gives the
  UI, the backend API, and guardrails through **one** upstream with zero extra Railway wiring.
- **`use_keyless = true` at Tyk.** Opik **already** enforces per-request identity: the SDK sends its
  own API key and the backend returns 401/403 on `/api/v1/private/*` without it. Putting a Tyk
  `auth_token` in front would mean **double auth** — every SDK call and every browser request would
  also need a Tyk key/header. That is awkward for the browser UI and adds friction for no security
  gain (Opik is still the identity authority). So Tyk's job here is the **edge layer**:
  rate-limit (120 req/60s), quota (200k/day), analytics, CORS, and a single managed hostname —
  while Opik keeps enforcing *who* you are.

**Trade-off documented:** if you want a **hard gateway boundary** (Tyk gates access *before*
traffic reaches Opik — e.g. machine-to-machine-only exposure, no browser UI), flip to the
`_auth_token_alternative` block in the JSON: `use_keyless:false` + an `auth_header_name`
(e.g. `x-amabile-key`) and issue keys to the existing aliases (`francisco-admin`, `n8n-indufix`,
`vinicius-devops`). Cost: the browser UI then needs the header injected (awkward), and SDK clients
carry **two** credentials. Recommendation stands: **keyless + rate-limit** unless a hard boundary is
explicitly required.

### Why path-based on `api.` instead of a new `obs.` host
No new DNS needed, no second TLS cert, no Cloudflare-proxy → Tyk → Cloudflare-proxy hairpin.
The script **supports** a dedicated `obs.amabileai.com.br` host too (set `NEW_SUBDOMAIN=obs`
+ `GATEWAY_CNAME_TARGET=...`), but the default/recommended path is **no DNS change**.

### CROSS-PROJECT REACHABILITY CAVEAT (important)
`*.railway.internal` **only resolves inside the same Railway project.** The Tyk gateway is a
**different** Railway project from the Opik stack (`opik-amabile`). Therefore Tyk **cannot** target
`backend.railway.internal` / `frontend.railway.internal`. It **must** target a **public** URL.
We use the Railway-issued public host `frontend-production-9b7e.up.railway.app` (stable,
Railway-terminated TLS) rather than `fabricaai.amabileai.com.br` to avoid double Cloudflare proxying.

---

## 2. Execution (operator runs these as `!`-prefixed commands)

PowerShell (this is a Windows operator box). Set the two secrets in the session env, then run the
bash script via the bundled Git-Bash / WSL `bash`. **No secrets are written to disk.**

```text
!$env:TYK_GW_SECRET = "<from Notion: Tyk admin secret — x-tyk-authorization>"
!$env:CLOUDFLARE_API_TOKEN = "<from Notion page 38ecb43f… token claude1 (cfat_…)>"
!bash scripts/item2-tyk-cloudflare.sh
```

Optional — also create a dedicated `obs.` hostname (otherwise the route is path-based on `api.`):

```text
!$env:NEW_SUBDOMAIN = "obs"
!$env:GATEWAY_CNAME_TARGET = "tyk-gateway-production-2e1b.up.railway.app"
!bash scripts/item2-tyk-cloudflare.sh
```

Optional — test the authenticated SDK path during verification:

```text
!$env:OPIK_API_KEY = "<AmabileAI API key from Notion>"
!$env:OPIK_WORKSPACE = "default"
!bash scripts/item2-tyk-cloudflare.sh
```

### What the script does (idempotent where possible)
1. **[0]** Lists current Tyk APIs (proves admin secret + base are correct; shows existing
   `bitrix24-indufix` for convention sanity).
2. **[a]** `GET /tyk/apis/{id}` → if present `PUT` (update), else `POST /tyk/apis` (create). Strips the
   editor-only `_*` keys from the JSON before sending.
3. **[b]** `GET /tyk/reload/group` — hot-reload all gateway workers.
4. **[c]** Cloudflare: resolves the zone id for `amabileai.com.br`; for the path-based default it
   **makes no DNS change**; for `NEW_SUBDOMAIN` it does **check-before-create** (PUT if the record
   exists, POST otherwise) — proxied CNAME, `ttl=1`.
5. **[d]** Verification curls (see checklist).

---

## 3. Verification checklist

After the script (and ~2-5s for the reload to propagate):

- [ ] `GET https://tyk-gateway-production-2e1b.up.railway.app/hello` → `200` (gateway alive).
- [ ] `GET https://api.amabileai.com.br/observability/` → `200`, returns the AmabileAI UI HTML.
- [ ] `GET https://api.amabileai.com.br/observability/api/v1/private/projects` **without** an Opik key
      → `401/403/500` from **Opik** (NOT a Tyk `"Key not authorised"` body). This proves keyless
      passthrough + Opik enforcing identity.
- [ ] (if `OPIK_API_KEY` exported) same path **with** `authorization: <key>` + `Comet-Workspace: default`
      → `200`.
- [ ] `GET https://api.amabileai.com.br/observability/guardrails/healthcheck` → `200` (`OK`).
- [ ] Rate limit sane: a burst >120 req/60s starts returning `429` from Tyk.
- [ ] Tyk dashboard/analytics shows traffic under api_id `opik-observability`.
- [ ] Existing direct route `https://fabricaai.amabileai.com.br/` still `200` (untouched).
- [ ] SDK smoke against the gateway:
      `OPIK_URL_OVERRIDE=https://api.amabileai.com.br/observability/api python sdk-examples/python_smoke.py`

---

## 4. Optional cutover (SEPARATE, explicitly-flagged — NOT part of this runbook's default run)

Only after the gateway route is verified and consumers are migrated:
1. Repoint or remove the direct `fabricaai` CNAME so the UI is reached **only** via Tyk, **or**
2. Keep both (UI direct on `fabricaai`, SDK via Tyk) — current recommendation, no cutover needed.

Do **not** delete the `fabricaai` CNAME in the same change window as the additive route. DNS/gateway
changes are irreversible-ish; keep the rollback path open.

---

## 5. Rollback

Fully reverses Item 2. Run as `!`-prefixed commands.

```text
# delete the Tyk API + reload
!$env:TYK_GW_SECRET = "<Tyk admin secret>"
!curl -fsSL -X DELETE -H "x-tyk-authorization: $env:TYK_GW_SECRET" "https://tyk-gateway-production-2e1b.up.railway.app/tyk/apis/opik-observability"
!curl -fsSL -H "x-tyk-authorization: $env:TYK_GW_SECRET" "https://tyk-gateway-production-2e1b.up.railway.app/tyk/reload/group"
```

```text
# delete the CNAME — ONLY if NEW_SUBDOMAIN was used (path-based default created NO DNS)
!$env:CLOUDFLARE_API_TOKEN = "<cfat_…>"
# resolve zone id, then the record id for obs.amabileai.com.br, then DELETE:
!curl -fsSL -H "Authorization: Bearer $env:CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones?name=amabileai.com.br"
!curl -fsSL -H "Authorization: Bearer $env:CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones/<ZONE_ID>/dns_records?name=obs.amabileai.com.br"
!curl -fsSL -X DELETE -H "Authorization: Bearer $env:CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones/<ZONE_ID>/dns_records/<RECORD_ID>"
```

Rollback is fast (<1 min): the Tyk delete + reload removes the route immediately; the direct
`fabricaai` route was never touched, so the platform stays reachable throughout.

---

## 6. Operational risks & assumptions

- **FINANCIAL PENDENCY (Notion): the Cloudflare invoice is failing.** If the Cloudflare **Pro plan**
  lapses for zone `amabileai.com.br`, the WAF/DDoS protection and proxy features degrade — affecting
  **both** the existing `fabricaai` route and this new gateway exposure. **Resolve the billing issue
  before relying on Cloudflare WAF as a security control.** Track to closure; this is an
  operational risk to the whole zone, not just Item 2.
- **Cross-project targeting (assumption):** Tyk reaches Opik only via the **public** Railway host.
  If that host changes (Railway redeploy under a new generated subdomain), update `target_url` in the
  JSON and re-run the script. Pin/verify the host before go-live.
- **Keyless trade-off:** Tyk does not gate identity on this route by design; Opik does. If a hard
  gateway boundary is later required, switch to the `_auth_token_alternative` block (Section 1).
- **No double Cloudflare proxy:** target is the Railway public host, not `fabricaai.…`, to avoid
  proxy hairpinning and conflicting TLS termination.
- **Reload is async:** allow a few seconds after `/tyk/reload/group` before verifying.
- **Secrets:** the Tyk admin secret and Cloudflare token are read from env only; never commit them.
  Source them from Notion at run time, per project policy.
```
