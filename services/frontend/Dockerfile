FROM ghcr.io/comet-ml/opik/opik-frontend:latest

# Create upstream blocks for Railway internal DNS (*.railway.internal)
# These files are separate from default.conf to avoid envsubst corruption
# Based on opik-ops skill §4.2 and official Opik nginx_default_local.conf
USER root
RUN echo 'upstream backend { server backend.railway.internal:8080; }' > /etc/nginx/conf.d/upstream-backend.conf && \
    echo 'upstream guardrails { server guardrails.railway.internal:5000; }' > /etc/nginx/conf.d/upstream-guardrails.conf && \
    chmod 0664 /etc/nginx/conf.d/upstream-backend.conf /etc/nginx/conf.d/upstream-guardrails.conf
USER nginx

# Copy our custom default.conf (uses upstream blocks, no hardcoded URLs)
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0664 /etc/nginx/conf.d/default.conf

# AmabileAI brand assets served from /amabile/* and used by sub_filter-injected
# <link>, <script>, and favicon overrides defined in default.conf.
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
