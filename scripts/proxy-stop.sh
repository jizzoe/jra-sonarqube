#!/bin/bash
# Host-side (runs on the ECS host via SSM): stop the TLS proxy and upload the
# certificate cache to S3 so the next cold start reuses the cert (Phase 2).
set -euo pipefail

BUCKET="${1:-jra-sonarqube-dumps}"

systemctl stop caddy 2>/dev/null || true

tar -czf - -C /var/lib/caddy . | aws s3 cp - "s3://${BUCKET}/caddy/data.tar.gz" >/dev/null
echo "==> cert cache uploaded to s3://${BUCKET}/caddy/data.tar.gz"
