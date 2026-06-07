FROM ghcr.io/comet-ml/opik/opik-frontend:latest

USER root

# STRATEGY:
# 1. The base image's /etc/nginx/conf.d/default.conf has a server block that
#    uses proxy_pass with an undefined variable, causing 500 errors.
# 2. Even when we COPY our config to default.conf, the patch script
#    (99-patch-nginx.conf.sh) processes it with envsubst.
# 3. We bypass this by:
#    a. Deleting the base image's default.conf (so it can't intercept requests)
#    b. Installing our config as 00-amabile.conf (loads first)
#    c. The base nginx.conf include /etc/nginx/conf.d/*.conf will still
#       pick up our config and any other configs that don't conflict.

# Step 1: Remove the base image's default.conf
RUN echo "=== Before: /etc/nginx/conf.d/ ===" && \
    ls -la /etc/nginx/conf.d/ 2>&1 && \
    echo "=== Deleting default.conf ===" && \
    rm -fv /etc/nginx/conf.d/default.conf 2>&1 && \
    echo "=== After deletion ===" && \
    ls -la /etc/nginx/conf.d/ 2>&1

# Step 2: Brand assets
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

# Step 3: Our custom config as 00-amabile.conf (loads alphabetically first)
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/00-amabile.conf
RUN chmod 0644 /etc/nginx/conf.d/00-amabile.conf && \
    echo "=== 00-amabile.conf installed ===" && \
    ls -la /etc/nginx/conf.d/ && \
    echo "=== first 3 lines ===" && \
    head -3 /etc/nginx/conf.d/00-amabile.conf

EXPOSE 5173
USER nginx
