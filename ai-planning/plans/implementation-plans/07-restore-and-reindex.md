# Slice 07 — Restore & reindex

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Implement the cold-start path: restore the newest verified dump, start SonarQube with an empty Elasticsearch directory, and reindex.

## Prerequisites

- Slice 06 (verified dumps exist in S3).

## Steps

1. Implement `restore`: download the newest dump, verify its SHA-256, and `pg_restore` into a fresh PostgreSQL container.
2. Ensure SonarQube starts with an empty `data/es8` directory so Elasticsearch rebuilds its indexes (never restore Elasticsearch data).
3. Health-check SonarQube and confirm indexes rebuild.
4. Run an end-to-end restore → reindex test from a clean teardown.

## Deliverables

- Restore script, reindex procedure, restore validation.

## Validation (exit criteria)

- A cold start from S3 yields a working SonarQube with reindexed Elasticsearch and the expected projects.

## Notes and risks

- This is the cold-start contract from the brief's §7. Secret recovery (Q6) must be proven here.
