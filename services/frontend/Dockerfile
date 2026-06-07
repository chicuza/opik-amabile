FROM ghcr.io/comet-ml/opik/opik-frontend:latest

# Debug: inspect base image state BEFORE we modify
USER root
RUN echo "=== STEP 1: base image state ===" && \
    echo "--- /etc/nginx/conf.d/ ---" && \
    ls -la /etc/nginx/conf.d/ && \
    echo "--- /docker-entrypoint.d/99-patch-nginx.conf.sh (first 3 lines) ---" && \
    head -3 /docker-entrypoint.d/99-patch-nginx.conf.sh

# Step 2: Remove the existing patch script and replace with no-op
RUN rm -f /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo "=== STEP 2: after rm ===" && \
    ls -la /docker-entrypoint.d/99-patch-nginx.conf.sh 2>&1 || echo "file is gone (expected)"

# Step 3: Create new no-op patch script
RUN printf '#!/bin/sh\nexit 0\n' > /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    chmod 0755 /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo "=== STEP 3: new patch script ===" && \
    ls -la /docker-entrypoint.d/99-patch-nginx.conf.sh && \
    echo "--- content ---" && \
    cat /docker-entrypoint.d/99-patch-nginx.conf.sh

# Step 4: Replace the default.conf with our custom one (with hardcoded URLs)
RUN rm -f /etc/nginx/conf.d/default.conf && \
    echo "=== STEP 4: after rm default.conf ===" && \
    ls -la /etc/nginx/conf.d/

COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0664 /etc/nginx/conf.d/default.conf && \
    echo "=== STEP 5: after COPY default.conf ===" && \
    ls -la /etc/nginx/conf.d/ && \
    echo "--- first 3 lines of new default.conf ---" && \
    head -3 /etc/nginx/conf.d/default.conf

# Step 5: Brand assets
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
USER nginx
