FROM ghcr.io/comet-ml/opik/opik-frontend:latest

# Remove the patch script that corrupts our custom config at runtime
RUN rm -f /docker-entrypoint.d/99-patch-nginx.conf.sh

# Copy upstream blocks for backend and guardrails (loaded before default.conf)
COPY --chown=nginx:nginx 00-backend.conf /etc/nginx/conf.d/00-backend.conf

# Copy default.conf as template
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf.template

# Process envsubst during build to avoid runtime corruption
RUN envsubst '${NGINX_PORT} ${OPIK_BACKEND_BASE_URL} ${OPIK_GUARDRAILS_BACKEND_URL}' \
    < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf && \
    rm /etc/nginx/conf.d/default.conf.template && \
    chmod 0664 /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/00-backend.conf

# AmabileAI brand assets served from /amabile/* and used by sub_filter-injected
# <link>, <script>, and favicon overrides defined in default.conf.
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
