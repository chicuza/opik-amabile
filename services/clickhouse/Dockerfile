FROM clickhouse/clickhouse-server:25.3.6.56-alpine

# Copiar apenas config.d (macros, zookeeper, etc.)
# NÃO copiar users.d - usar variáveis de ambiente nativas do ClickHouse
# (CLICKHOUSE_USER, CLICKHOUSE_PASSWORD, CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT)
COPY config.d/ /etc/clickhouse-server/config.d/

EXPOSE 8123 9000 9009

COPY clear-opik-zk.sh /usr/local/bin/clear-opik-zk.sh
RUN chmod +x /usr/local/bin/clear-opik-zk.sh

# Entrypoint: cleans stale status file, optionally clears the opik DB so Liquibase rebuilds
# from scratch (set CH_CLEAR_OPIK_DB=<token> to trigger, then unset on next deploy), then starts CH.
ENTRYPOINT ["sh","-c","echo '[entrypoint] removing stale status file if present' && rm -f /var/lib/clickhouse/status && /entrypoint.sh &  SERVER_PID=$!; /usr/local/bin/clear-opik-zk.sh; wait $SERVER_PID"]
