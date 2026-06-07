#!/bin/sh
# Custom AmabileAI entrypoint that bypasses the Opik patch script
# which corrupts nginx config with envsubst.

# Disable the original patch script (may fail silently if read-only)
chmod -R 0777 /docker-entrypoint.d/ 2>/dev/null || true
rm -f /docker-entrypoint.d/99-patch-nginx.conf.sh 2>/dev/null || true

# Install our no-op patch script using multiple fallback methods
cat > /docker-entrypoint.d/99-patch-nginx.conf.sh << 'EOF'
#!/bin/sh
echo "Patcher disabled by AmabileAI rebrand"
exit 0
EOF
chmod 0755 /docker-entrypoint.d/99-patch-nginx.conf.sh 2>/dev/null || true

# Verify our patch script exists
echo "=== Patch script content (after our install) ==="
cat /docker-entrypoint.d/99-patch-nginx.conf.sh 2>&1 || echo "PATCH SCRIPT NOT FOUND"

# Execute the original entrypoint
exec /docker-entrypoint.sh "$@"
