# Slice 01 — IAM workload roles & secrets

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Create the least-privilege roles the Terraform provider and ECS tasks need, and the Secrets Manager store for database/session secrets (resolves open question Q6).

## Prerequisites

- Slice 00 (state backend, budget, domain/hosted zone).

## Steps

1. Create `jra-platform-terraform` with a policy scoped to the resource inventory (EC2, ECS, S3, DynamoDB, Route 53, Budgets, Secrets Manager, CloudWatch Logs) plus `iam:PassRole` limited to the specific roles it creates.
2. Create `jra-sonarqube-deploy` (deploy-only) and `jra-sonarqube-task` (runtime: S3 dump read/write, `secretsmanager:GetSecretValue` on its own secret ARNs, CloudWatch Logs).
3. Add the `jra-platform-terraform` CLI profile (`source_profile = jra-platform-bootstrap` or `joe-rice-admin`).
4. Create Secrets Manager secrets for the PostgreSQL superuser, the SonarQube database user, and the SonarQube admin password; grant the task role read on those ARNs only.
5. Record a recovery note for secret values outside the repository.

## Deliverables

- IAM roles + inline/customer policies; Secrets Manager secrets (values set out-of-band).

## Validation (exit criteria)

- `aws sts get-caller-identity --profile jra-platform-terraform` succeeds.
- `simulate-principal-policy` shows the task role can read only its own secrets.

## Notes and risks

- Secret *values* never enter Terraform state or the repository; only ARN references appear in state.
- Role names follow the IAM bootstrap brief; no Jenkins roles are created.
