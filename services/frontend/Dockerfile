FROM ghcr.io/comet-ml/opik/opik-frontend:latest

# Disable the patch script that corrupts our config with envsubst
# We handle variable substitution manually to avoid corruption
USER root
RUN echo '#!/bin/sh' > /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo '# Disabled: we use pre-processed config' >> /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    chmod +x /docker-entrypoint.d/99-patch-nginx.conf.sh

# Copy our custom default.conf with hardcoded URLs (no envsubst needed)
# Using hardcoded URLs because envsubst corrupts nginx variables like $backend_upstream
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0664 /etc/nginx/conf.d/default.conf

# AmabileAI brand assets served from /amabile/*
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
USER nginx
