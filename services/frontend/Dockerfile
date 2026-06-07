FROM ghcr.io/comet-ml/opik/opik-frontend:latest

USER root

# Make all docker-entrypoint.d files writable
RUN echo "=== BEFORE: listing entrypoint.d ===" && \
    ls -la /docker-entrypoint.d/ && \
    echo "=== Making files writable ===" && \
    chmod -R 0777 /docker-entrypoint.d/ && \
    echo "=== Deleting patch script ===" && \
    rm -fv /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo "=== Creating no-op patch script via tee ===" && \
    echo '#!/bin/sh' | tee /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo '# Disabled by AmabileAI rebrand Dockerfile' | tee -a /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo 'exit 0' | tee -a /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    chmod 0755 /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo "=== AFTER: patch script ===" && \
    cat /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    ls -la /docker-entrypoint.d/99-patch-nginx.conf.sh

# Make conf.d writable
RUN echo "=== BEFORE: conf.d ===" && \
    ls -la /etc/nginx/conf.d/ && \
    chmod -R 0777 /etc/nginx/conf.d/ && \
    rm -fv /etc/nginx/conf.d/default.conf

# Copy our custom default.conf
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN echo "=== AFTER: conf.d ===" && \
    ls -la /etc/nginx/conf.d/ && \
    echo "=== first lines of new default.conf ===" && \
    head -10 /etc/nginx/conf.d/default.conf && \
    chmod 0664 /etc/nginx/conf.d/default.conf

# Brand assets
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
USER nginx
