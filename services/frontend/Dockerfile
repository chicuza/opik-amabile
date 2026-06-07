FROM ghcr.io/comet-ml/opik/opik-frontend:latest

# Copy our custom default.conf with dynamic DNS resolution
# Uses set $var + proxy_pass $var pattern for runtime DNS resolution
# This is required for Railway's internal DNS (*.railway.internal)
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN chmod 0664 /etc/nginx/conf.d/default.conf

# AmabileAI brand assets served from /amabile/* and used by sub_filter-injected
# <link>, <script>, and favicon overrides defined in default.conf.
COPY --chown=nginx:nginx assets/ /usr/share/nginx/html/amabile/

EXPOSE 5173
