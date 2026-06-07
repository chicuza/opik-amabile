FROM ghcr.io/comet-ml/opik/opik-frontend:latest

USER root

# Test: create a UNIQUE marker file with a name that doesn't conflict
RUN echo "BUILD_TEST_$(date +%s)" > /amabile-build-marker.txt && \
    cat /amabile-build-marker.txt

# Try to copy the default.conf
COPY --chown=nginx:nginx default.conf /etc/nginx/conf.d/default.conf
RUN echo "=== AFTER COPY: ===" && \
    ls -la /etc/nginx/conf.d/ && \
    echo "=== content of default.conf ===" && \
    cat /etc/nginx/conf.d/default.conf && \
    echo "=== amabile-build-marker.txt ===" && \
    cat /amabile-build-marker.txt

EXPOSE 5173
USER nginx
