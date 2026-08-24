#!/bin/bash
# Cold-stop backup: dump PostgreSQL (custom format), upload to S3 with a
# SHA-256 checksum, verify the upload, and write restore metadata.
set -euo pipefail

BUCKET="${BUCKET:-jra-sonarqube-dumps}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
KEY="sonar-${TS}.dump"
DUMP="/tmp/${KEY}"

CID="$(docker ps --filter name=postgres --format '{{.ID}}' | head -1)"
if [ -z "$CID" ]; then
  echo "ERROR: postgres container not running" >&2
  exit 1
fi

echo "==> Dumping PostgreSQL (pg_dump -Fc) from container $CID"
docker exec "$CID" pg_dump -Fc -U sonar -d sonar > "$DUMP"

echo "==> Computing SHA-256"
SHA="$(sha256sum "$DUMP" | awk '{print $1}')"
echo "    sha256=${SHA}"

echo "==> Uploading to s3://${BUCKET}/${KEY}"
aws s3 cp "$DUMP" "s3://${BUCKET}/${KEY}" --metadata "sha256=${SHA}"

echo "==> Verifying upload"
UPLOADED="$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --query 'Metadata.sha256' --output text)"
if [ "$UPLOADED" != "$SHA" ]; then
  echo "ERROR: checksum mismatch (local=${SHA} remote=${UPLOADED})" >&2
  exit 1
fi

echo "==> Writing restore metadata"
printf '%s %s\n' "$KEY" "$SHA" | aws s3 cp - "s3://${BUCKET}/metadata/latest.txt"

echo "Backup verified: ${KEY}"
