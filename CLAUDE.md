# AmabileAI Observability — Diretrizes do Projeto

## Identidade

- **Nome:** AmabileAI Observability
- **Stack:** Opik (Comet ML) self-hosted no Railway
- **URL pública:** https://fabricaai.amabileai.com.br
- **Railway Direct:** https://frontend-production-9b7e.up.railway.app
- **GitHub:** https://github.com/chicuza/opik-amabile

## Infraestrutura Railway

- **Project:** `opik-amabile` (ID: `7ccaf972-0b24-46f2-a888-e877cb0cad7c`)
- **Environment:** `production` (ID: `88dc2fd7-cea1-4e01-86ac-07cf7d6d39ac`)
- **Serviços:** 10 (frontend, backend, clickhouse, mysql, redis, zookeeper, minio, python-backend, guardrails, keycloak)

## Regras de Rebrand (OBRIGATÓRIAS)

Este projeto é um **fork rebranded** do Opik upstream. O rebrand é **FRONTEND-ONLY** e vive no
serviço `frontend` via Dockerfile custom sobre `opik-frontend:latest`.

### NUNCA fazer:
- Usar imagem stock `opik-frontend:latest` diretamente (apaga o rebrand)
- Remover o overlay (default.conf, brand.css, brand-cleanup.js)
- Expor "Comet Opik", "Comet ML", ou links comet.com ao usuário
- Renomear variáveis `OPIK_*` (são SDK contract do PyPI `opik`)
- Fazer deploy sem rodar o VALIDATION_CHECKLIST

### SEMPRE fazer:
- Usar o Dockerfile custom em `services/frontend/Dockerfile`
- Preservar as 27 regex replacements em `brand-cleanup.js`
- Rodar `VALIDATION_CHECKLIST.md` após qualquer deploy
- Consultar skill `opik-rebrand-amabile` antes de mexer no frontend

## Skills Obrigatórias

- **`opik-rebrand-amabile`** — protocolo de proteção do rebrand (Claude + OpenCode)
- **`opik-ops`** — operações Railway/ClickHouse/Docker
- **`opik-dev`** — desenvolvimento com SDK Opik
- **`opik-mcp`** — integração MCP server

## Estrutura do Projeto

```
opic-amabile/
├── services/
│   ├── frontend/          # ← REBRAND (Dockerfile + overlay)
│   │   ├── Dockerfile     # FROM opik-frontend:latest + COPY overlay
│   │   ├── default.conf   # nginx: sub_filter + upstreams Railway
│   │   ├── railway.json   # builder: DOCKERFILE
│   │   └── assets/        # brand.css, brand-cleanup.js, icons, logo
│   ├── backend/           # Stock upstream (Java)
│   ├── clickhouse/        # Custom Dockerfile (self-heal + lockfile fix)
│   ├── python-backend/    # Stock upstream
│   ├── guardrails/        # Stock upstream
│   ├── mysql/             # Railway template
│   ├── redis/             # Railway template
│   ├── zookeeper/         # Stock image
│   ├── minio/             # bitnamilegacy/minio
│   └── tyk/               # API gateway config
├── scripts/               # Deploy scripts (bootstrap, set-env, verify)
├── sdk-examples/          # Python/TypeScript smoke tests
├── tools/                 # Railway CLI binary
├── STATUS.md              # Status atual do deploy
└── README.md              # Visão geral da arquitetura
```

## Credenciais

- **Railway API Token:** em `scripts/.deploy.env` (gitignored)
- **ClickHouse password:** hardcoded em `services/clickhouse/users.d/opik_user.xml`
  (NÃO usar `from_env` — Railway não injeta a tempo)
- **OPIK_API_KEY:** gerar via UI em https://fabricaai.amabileai.com.br

## Known Issues

- Backend pode crashar com `REPLICA_ALREADY_EXISTS` no ClickHouse → ver DEPLOY_PROTOCOL.md
- ClickHouse `from_env="CLICKHOUSE_PASSWORD"` não funciona no Railway → usar hardcoded
- Guardrails retorna 500 sem variáveis configuradas (`OPIK_GUARDRAILS_DEVICE`, `HF_HOME`)
- `client_max_body_size 2G` no nginx — potencialmente abusável
