# Slice 05 — SonarQube container & service

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Run SonarQube Community Build in a second container and expose it only within the private network on port 9000.

## Prerequisites

- Slice 04 (PostgreSQL healthy with the `sonar` database).

## Steps

1. Define the SonarQube task definition using a pinned Community Build image; mount the EBS volume for `data` (separate subpath from `PGDATA`).
2. Configure the database connection to PostgreSQL via Secrets Manager.
3. Create a service (desired count 1) with an internal-only security-group rule allowing 9000 from the application security group.
4. Add a health check against `/api/system/status`.

## Deliverables

- `aws_ecs_task_definition` (SonarQube), `aws_ecs_service`, internal 9000 security-group rule.

## Validation (exit criteria)

- `/api/system/status` returns UP; the UI is reachable only through an SSM port-forward tunnel, not publicly.

## Notes and risks

- No public exposure; reserve 443 for Phase 2. Community Build supports main-branch analysis only.
