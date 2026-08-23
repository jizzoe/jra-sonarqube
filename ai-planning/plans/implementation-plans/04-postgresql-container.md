# Slice 04 — PostgreSQL container

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Run PostgreSQL (not RDS) on the ECS host with a disposable EBS volume, seeded from Secrets Manager.

## Prerequisites

- Slice 03 (cluster + host running).

## Steps

1. Define the PostgreSQL task definition; inject database credentials from Secrets Manager.
2. Mount a fresh gp3 EBS volume (`configuredAtLaunch`) for `PGDATA`; give the container a stable name for later `pg_dump`.
3. Start the container and run an init step that creates the `sonar` database and user.
4. Add a container health check using `pg_isready`.

## Deliverables

- `aws_ecs_task_definition` (PostgreSQL), EBS volume configuration, init SQL, health check.

## Validation (exit criteria)

- `pg_isready` passes; the `sonar` database exists; data survives a container restart within the session.

## Notes and risks

- No RDS. PostgreSQL is the durable source of truth; Elasticsearch is rebuilt (slice 07). EBS is disposable and destroyed on cold stop.
