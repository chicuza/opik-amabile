FROM ghcr.io/comet-ml/opik/opik-frontend:latest

USER root

# Copy our minimal test config as default.conf
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0644 /etc/nginx/conf.d/default.conf

# Brand assets
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
USER nginx
