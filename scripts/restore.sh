#!/bin/bash
# Cold-start restore: download the newest verified dump, verify its SHA-256,
# pg_restore into PostgreSQL, and clear Elasticsearch data to force reindex.
set -euo pipefail

BUCKET="${BUCKET:-jra-sonarqube-dumps}"

META="$(aws s3 cp "s3://${BUCKET}/metadata/latest.txt" -)"
KEY="$(echo "$META" | awk '{print $1}')"
EXPECTED="$(echo "$META" | awk '{print $2}')"
DUMP="/tmp/${KEY}"

echo "==> Downloading s3://${BUCKET}/${KEY}"
aws s3 cp "s3://${BUCKET}/${KEY}" "$DUMP"

echo "==> Verifying SHA-256"
ACTUAL="$(sha256sum "$DUMP" | awk '{print $1}')"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "ERROR: checksum mismatch (expected ${EXPECTED}, got ${ACTUAL})" >&2
  exit 1
fi
echo "    sha256 OK"

echo "==> Restoring into PostgreSQL"
CID="$(docker ps --filter name=postgres --format '{{.ID}}' | head -1)"
if [ -z "$CID" ]; then
  echo "ERROR: postgres container not running" >&2
  exit 1
fi
docker exec -i "$CID" pg_restore --clean --if-exists -U sonar -d sonar < "$DUMP"

echo "==> Clearing Elasticsearch data (forces reindex from the DB)"
rm -rf /var/lib/sonarqube-data/es8

echo "Restore complete: ${KEY}"
