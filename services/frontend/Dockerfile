FROM ghcr.io/comet-ml/opik/opik-frontend:latest

USER root

# Debug what we have at every step
RUN echo "=== STEP A: base image /etc/nginx/conf.d/ ===" && \
    ls -la /etc/nginx/conf.d/ 2>&1

# Copy our default.conf FIRST
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN echo "=== STEP B: after COPY ===" && \
    ls -la /etc/nginx/conf.d/ 2>&1 && \
    echo "--- first 5 lines ---" && \
    head -5 /etc/nginx/conf.d/default.conf 2>&1 && \
    echo "--- file size ---" && \
    wc -l /etc/nginx/conf.d/default.conf 2>&1

# Verify COPY worked by reading specific lines
RUN grep -c "listen 5173" /etc/nginx/conf.d/default.conf && \
    echo "listen 5173 found OK" || \
    echo "listen 5173 NOT FOUND - COPY FAILED"

# Brand assets
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
USER nginx
