# Prompt de retomada — colar após reiniciar o Claude Code

Reinicie nesta pasta com:

```
claude --dangerously-skip-permissions
```

Depois cole o prompt abaixo:

---

Estou em `C:\Users\chicu\opic-amabile` — deploy do AmabileAI Observability (fork do Opik) no Railway, projeto `opik-amabile` (env chamado `production`, mas é ambiente DEV/PoC; a produção real é na AWS). Execute o deploy completo agora rodando:

```
bash scripts/run-all.sh
```

Esse orquestrador faz, em ordem, lendo os tokens de `scripts/.deploy.env`:
1. **Item 3** (`scripts/deploy-fix.sh`): rebuild do serviço `clickhouse` com o self-heal não-destrutivo em `services/clickhouse/clear-opik-zk.sh` (recupera o znode de réplica órfão que causa `REPLICA_ALREADY_EXISTS`), depois `redeploy` do `backend` pra re-rodar as migrações Liquibase.
2. **Verify** (`scripts/verify-fix.sh`): health público + confirma que `REPLICA_ALREADY_EXISTS` sumiu dos logs do backend.
3. **Item 2** (`scripts/item2-tyk-cloudflare.sh`): só se o verify passar — cria a API no Tyk (`/observability/` em `api.amabileai.com.br`, rota aditiva, keyless) + CNAME no Cloudflare. NÃO faz cutover do `fabricaai` atual.

Sua tarefa:
- Rode o `run-all.sh` e **interprete os logs de cada etapa**: confirme `[clear-opik-zk] reclaimed orphan replica` nos logs do ClickHouse, ausência de `REPLICA_ALREADY_EXISTS` e sucesso do Liquibase no backend.
- Se o item 3 falhar, siga a árvore de decisão de rollback em `scripts/RUNBOOK-item3.md` (`scripts/rollback-fix.sh`).
- Se o item 2 falhar, rollback = `DELETE /tyk/apis/{id}` + reload e remover o CNAME (`scripts/RUNBOOK-item2.md`).
- **NÃO rotacione credenciais** (decisão do usuário).
- Contexto técnico completo: `STATUS.md` (seção "Phase 4 fixes") e `C:\Users\chicu\.claude\plans\architect-reviewer-agent-error-detectiv-staged-lamport.md`.

Comece executando `bash scripts/run-all.sh` e me reportando o resultado de cada fase.

---
