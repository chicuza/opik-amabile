FROM ghcr.io/comet-ml/opik/opik-frontend:latest

USER root

# Test: copy our minimal default.conf (build context is services/frontend/)
COPY default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0644 /etc/nginx/conf.d/default.conf && \
    echo "=== Build: /etc/nginx/conf.d/ ===" && \
    ls -la /etc/nginx/conf.d/ && \
    echo "=== Build: content of default.conf ===" && \
    cat /etc/nginx/conf.d/default.conf

# Brand assets
COPY assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
USER nginx
