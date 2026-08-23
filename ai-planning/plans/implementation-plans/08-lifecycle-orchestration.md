# Slice 08 — Lifecycle orchestration

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Wrap the pieces into idempotent `start` and `cold-stop` workflows with health checks.

## Prerequisites

- Slices 06 + 07 (both backup and restore paths work).

## Steps

1. Implement `start`: `terraform apply` (network/cluster/task/service) → restore (slice 07) → reindex → health gate.
2. Implement `cold-stop`: block new scans → wait for in-flight analysis → `backup-and-verify` (slice 06) → `terraform destroy` of EC2/EBS (and release any public IP in Phase 2).
3. Add a status/health check and minimal CloudWatch Logs.
4. Document the runbooks (start / stop / recover).

## Deliverables

- `start` and `cold-stop` orchestration (scripts or Makefile), health check, runbook.

## Validation (exit criteria)

- Two consecutive full start → stop → start cycles succeed with no manual steps.

## Notes and risks

- Keep orchestration as scripts over `terraform apply` rather than embedding lifecycle logic in state where practical.
