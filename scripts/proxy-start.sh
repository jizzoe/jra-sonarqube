#!/bin/bash
# Host-side (runs on the ECS host via SSM): write the Caddyfile, restore the
# cached certificate, and start the public TLS proxy (Phase 2).
set -euo pipefail

DOMAIN="${1:?domain required}"
TASK_IP="${2:?task ip required}"
ZONE_ID="${3:?hosted zone id required}"
BUCKET="${4:-jra-sonarqube-dumps}"

mkdir -p /etc/caddy /var/lib/caddy

# Restore the cached certificate/storage so we reuse the cert across cold
# starts (avoids re-issuing and hitting Let's Encrypt's 5-duplicate-cert/week
# rate limit).
if aws s3 cp "s3://${BUCKET}/caddy/data.tar.gz" /tmp/caddy-data.tar.gz >/dev/null 2>&1; then
  tar -xzf /tmp/caddy-data.tar.gz -C /var/lib/caddy
  rm -f /tmp/caddy-data.tar.gz
  echo "==> restored cert cache"
else
  echo "==> no cert cache (first issuance)"
fi

cat > /etc/caddy/Caddyfile <<CADDY
${DOMAIN} {
    tls {
        dns route53 {
            hosted_zone_id ${ZONE_ID}
        }
    }
    reverse_proxy http://${TASK_IP}:9000
}

# Localhost-only plain-HTTP bridge, so the UI is reachable via SSM port-forward
# before public DNS/TLS is live.
http://127.0.0.1:8080 {
    reverse_proxy http://${TASK_IP}:9000
}
CADDY

systemctl daemon-reload
if systemctl is-active --quiet caddy; then
  systemctl restart caddy
else
  systemctl enable --now caddy
fi
echo "==> Caddy serving ${DOMAIN} -> ${TASK_IP}:9000"
