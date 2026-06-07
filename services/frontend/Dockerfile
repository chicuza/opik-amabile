FROM ghcr.io/comet-ml/opik/opik-frontend:latest

# Disable the patch script that corrupts our config with envsubst
# We use --force-rm, chmod first, and cat to overwrite robustly
USER root
RUN cat > /docker-entrypoint.d/99-patch-nginx.conf.sh << 'EOF'
#!/bin/sh
# Disabled by AmabileAI rebrand Dockerfile
echo "Patcher disabled - using pre-processed config"
exit 0
EOF
RUN chmod 0755 /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    cat /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    ls -la /docker-entrypoint.d/99-patch-nginx.conf.sh

# Copy our custom default.conf with hardcoded URLs (no envsubst needed)
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0664 /etc/nginx/conf.d/default.conf && \
    head -5 /etc/nginx/conf.d/default.conf

# AmabileAI brand assets served from /amabile/*
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
USER nginx
