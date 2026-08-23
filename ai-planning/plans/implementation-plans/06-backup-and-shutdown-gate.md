# Slice 06 — Backup & shutdown gate

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Implement the cold-stop path: block work, dump PostgreSQL, upload to S3 with checksum + metadata, verify, then allow teardown (resolves open question Q5).

## Prerequisites

- Slice 05 (a running application to back up).

## Steps

1. Resolve Q5 before coding: RPO, schedule, S3 retention, encryption/key policy, checksum format, and restore-validation criteria (default: backup each session, retain 30 days, SHA-256 checksum).
2. Implement `backup-and-verify`: `pg_dump` → gzip → `aws s3 cp` with SHA-256 to the encrypted bucket; write restore metadata (timestamp, file name, checksum).
3. Enforce the shutdown gate: teardown is blocked unless S3 object existence, checksum, and metadata verification all succeed.
4. Write the retention/expiration rule for the dump prefix.

## Deliverables

- Backup script, S3 bucket/object configuration, verification step, teardown guard, retention rule.

## Validation (exit criteria)

- A dump uploads and verifies; a deliberate teardown without a valid dump is rejected.

## Notes and risks

- The most recent verified backup is the recovery point; a failed backup or upload must prevent destruction.
