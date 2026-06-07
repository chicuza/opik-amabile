#!/usr/bin/env bash
# Create proxied CNAME fabricaai.amabileai.com.br -> <railway-cname-target>.
#
# Required env:
#   CLOUDFLARE_API_TOKEN
#   RAILWAY_CNAME_TARGET   (e.g. abc123.up.railway.app — get from Railway UI after adding the custom domain)
#
# Optional:
#   SUBDOMAIN              default: fabricaai
#   ZONE_NAME              default: amabileai.com.br

set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN required}"
: "${RAILWAY_CNAME_TARGET:?RAILWAY_CNAME_TARGET required}"

SUBDOMAIN="${SUBDOMAIN:-fabricaai}"
ZONE_NAME="${ZONE_NAME:-amabileai.com.br}"
RECORD_NAME="${SUBDOMAIN}.${ZONE_NAME}"

api() {
  curl -fsSL -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
              -H "Content-Type: application/json" "$@"
}

echo ">>> verify token"
api "https://api.cloudflare.com/client/v4/user/tokens/verify" | python -c "import sys,json; d=json.load(sys.stdin); print(d['result']['status'])"

echo ">>> resolve zone $ZONE_NAME"
ZONE_ID=$(api "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
  | python -c "import sys,json; print(json.load(sys.stdin)['result'][0]['id'])")
echo "    zone_id=$ZONE_ID"

echo ">>> check existing record"
EXISTING=$(api "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_NAME" \
  | python -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['id'] if r else '')")

PAYLOAD=$(python -c "
import json
print(json.dumps({
  'type': 'CNAME',
  'name': '$SUBDOMAIN',
  'content': '$RAILWAY_CNAME_TARGET',
  'proxied': True,
  'ttl': 1,
  'comment': 'Opik frontend on Railway (managed by opic-amabile)'
}))")

if [ -n "$EXISTING" ]; then
  echo ">>> updating existing record $EXISTING"
  api -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$EXISTING" \
      --data "$PAYLOAD" | python -m json.tool
else
  echo ">>> creating new CNAME"
  api -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      --data "$PAYLOAD" | python -m json.tool
fi

echo ">>> done. Cloudflare SSL/TLS mode for zone should be 'Full (strict)'."
