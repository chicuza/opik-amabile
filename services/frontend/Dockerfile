FROM ghcr.io/comet-ml/opik/opik-frontend:latest

# Replace the patch script with a no-op to prevent it from corrupting our config
RUN echo '#!/bin/sh' > /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo '# No-op: we use our own custom config' >> /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    chmod +x /docker-entrypoint.d/99-patch-nginx.conf.sh

# Copy our custom default.conf (hardcoded URLs, no envsubst needed)
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0664 /etc/nginx/conf.d/default.conf

# AmabileAI brand assets served from /amabile/* and used by sub_filter-injected
# <link>, <script>, and favicon overrides defined in default.conf.
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
