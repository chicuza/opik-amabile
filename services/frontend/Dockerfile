FROM ghcr.io/comet-ml/opik/opik-frontend:latest

USER root

# Install custom entrypoint that disables the patch script
COPY amabile-entrypoint.sh /amabile-entrypoint.sh
RUN chmod 0755 /amabile-entrypoint.sh

# Also try to disable the patch script at build time (best effort)
RUN chmod -R 0777 /docker-entrypoint.d/ 2>/dev/null; \
    rm -f /docker-entrypoint.d/99-patch-nginx.conf.sh 2>/dev/null; \
    echo '#!/bin/sh' > /docker-entrypoint.d/99-patch-nginx.conf.sh 2>/dev/null; \
    echo 'exit 0' >> /docker-entrypoint.d/99-patch-nginx.conf.sh 2>/dev/null; \
    chmod 0755 /docker-entrypoint.d/99-patch-nginx.conf.sh 2>/dev/null; \
    echo "=== Build-time patch script content ===" && \
    cat /docker-entrypoint.d/99-patch-nginx.conf.sh 2>&1 || echo "build-time install failed (will use entrypoint)"

# Copy our custom default.conf with hardcoded URLs
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0664 /etc/nginx/conf.d/default.conf && \
    head -3 /etc/nginx/conf.d/default.conf

# Brand assets
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173

# Use our custom entrypoint that disables the patch script
ENTRYPOINT ["/amabile-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
