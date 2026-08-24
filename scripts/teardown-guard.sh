#!/bin/bash
# Shutdown gate: teardown is allowed only if a verified dump exists in S3.
set -euo pipefail

BUCKET="${BUCKET:-jra-sonarqube-dumps}"

echo "==> Checking for a verified backup"
META="$(aws s3 cp "s3://${BUCKET}/metadata/latest.txt" - 2>/dev/null || true)"
if [ -z "$META" ]; then
  echo "REJECTED: no backup metadata found - cannot teardown." >&2
  exit 1
fi

KEY="$(echo "$META" | awk '{print $1}')"
EXPECTED="$(echo "$META" | awk '{print $2}')"
ACTUAL="$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --query 'Metadata.sha256' --output text 2>/dev/null || true)"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "REJECTED: backup ${KEY} not verified (expected ${EXPECTED}, got ${ACTUAL})." >&2
  exit 1
fi

echo "ALLOWED: verified backup ${KEY} exists."
