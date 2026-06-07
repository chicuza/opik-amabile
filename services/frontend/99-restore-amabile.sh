#!/bin/sh
# Restore our custom default.conf after Opik's patch script corrupts it
# This script runs AFTER 99-patch-nginx.conf.sh

cat > /etc/nginx/conf.d/default.conf << 'EOF'
client_max_body_size 2G;
client_header_buffer_size 16k;
large_client_header_buffers 4 64k;

server {
    listen ${NGINX_PORT} default_server;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # AmabileAI brand overlay
    location /amabile/brand.css {
        alias /usr/share/nginx/html/amabile/brand.css;
        access_log off;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }
    location /amabile/brand-cleanup.js {
        alias /usr/share/nginx/html/amabile/brand-cleanup.js;
        access_log off;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }
    location /amabile/ {
        alias /usr/share/nginx/html/amabile/;
        access_log off;
        expires 1h;
    }
    location = /favicon.ico {
        alias /usr/share/nginx/html/amabile/favicon.ico;
        access_log off;
        expires 1h;
    }

    location /health {
        add_header Content-Type text/plain;
        access_log off;
        return 200 "healthy\n";
    }

    location @api {
        rewrite /api/(.*) /$1 break;
        proxy_pass http://backend:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90;
        proxy_connect_timeout 90;
        proxy_send_timeout 90;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /api/ {
        try_files /dev/null @api;
    }

    location @guardrails {
        rewrite /guardrails/(.*) /$1 break;
        proxy_pass http://guardrails:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90;
        proxy_connect_timeout 90;
        proxy_send_timeout 90;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /guardrails/ {
        try_files /dev/null @guardrails;
    }

    location / {
        gzip off;
        sub_filter_once off;
        sub_filter_types text/html;
        sub_filter '<title>Comet Opik</title>' '<title>AmabileAI Observability</title>';
        sub_filter '<title>Opik</title>' '<title>AmabileAI Observability</title>';
        sub_filter '/favicon.ico' '/amabile/favicon.ico';
        sub_filter '</head>' '<link rel="apple-touch-icon" sizes="180x180" href="/amabile/amabile-icon-192.png"><link rel="icon" type="image/png" sizes="32x32" href="/amabile/amabile-icon-32.png"><link rel="manifest" href="/amabile/manifest.webmanifest"><link rel="stylesheet" href="/amabile/brand.css?v=7"></head>';
        sub_filter '</body>' '<script src="/amabile/brand-cleanup.js?v=7" defer></script></body>';
        try_files $uri $uri/ /index.html;
    }

    add_header X-Trace-ID $otel_trace_id;
}
EOF

# Process envsubst on our custom config
envsubst '${NGINX_PORT}' < /etc/nginx/conf.d/default.conf > /etc/nginx/conf.d/default.conf.tmp
mv /etc/nginx/conf.d/default.conf.tmp /etc/nginx/conf.d/default.conf
