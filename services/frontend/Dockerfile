FROM ghcr.io/comet-ml/opik/opik-frontend:latest

USER root

# Copy our additional config (loads before base default.conf due to 00- prefix)
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/00-amabile.conf
RUN chmod 0644 /etc/nginx/conf.d/00-amabile.conf && \
    echo "=== /etc/nginx/conf.d/ contents ===" && \
    ls -la /etc/nginx/conf.d/ && \
    echo "=== 00-amabile.conf first lines ===" && \
    head -3 /etc/nginx/conf.d/00-amabile.conf

# Copy brand assets to nginx html directory
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
USER nginx
