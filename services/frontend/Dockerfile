FROM ghcr.io/comet-ml/opik/opik-frontend:latest

# Overlay nginx default.conf with Railway-internal upstream hostnames and
# the AmabileAI brand overlay (sub_filter rules, custom favicon, brand assets).
# The baked image's conf points at literal "backend:8080" via Docker's embedded resolver,
# which doesn't exist on Railway. We swap in `*.railway.internal` upstreams.
# Opik's /docker-entrypoint.d/99-patch-nginx.conf.sh runs envsubst on every
# file in /etc/nginx/conf.d/, substituting ${NGINX_PORT}, OTEL_*, etc. and
# writes the result back to the same path. It needs write permission for that.
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0664 /etc/nginx/conf.d/default.conf

# AmabileAI brand assets served from /amabile/* and used by sub_filter-injected
# <link>, <script>, and favicon overrides defined in default.conf.
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
