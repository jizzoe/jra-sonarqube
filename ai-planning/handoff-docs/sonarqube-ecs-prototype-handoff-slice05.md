# SonarQube ECS Prototype — Handoff (Slice 05 onward)

Date: 2026-08-24
Repo: jra-sonarqube (main @ 3666126, pushed to origin/main)
Purpose: self-contained context for a fresh session to continue from the end of Slice 04 into Slice 05 (and the rest of the roadmap).

## Delivery cadence

Unchanged from the original handoff: work one slice at a time in roadmap order, treat each
`ai-planning/plans/implementation-plans/NN-*.md` as that slice's work spec (Goal / Steps /
Deliverables / Validation), treat "Validation (exit criteria)" as the done gate, and emit a
slice summary after each slice + a milestone summary at milestone boundaries. The referenced
cadence skill brief is at:

`sdd-milestone-slice-delivery-skill.md` in repo `joericearchitect-ai-skills` (apply the cadence "as if it were a skill"; execute from the implementation plans).

## Progress so far (all pushed to origin/main)

| Commit | Slice | Status |
| --- | --- | --- |
| 4db241c | 00 Account foundations | done — state backend (S3+DynamoDB), budget alarm, Route 53 hosted zone |
| 4f07527 | 01 IAM roles & secrets | done — 3 roles, 3 Secrets Manager secrets (Q6 resolved: Secrets Manager) |
| 675ba23 | 02 VPC & access | done — VPC + public subnet + IGW, default-deny SGs, ECS host instance profile |
| 4673777 | Option 2 (network change) | done — dropped SSM VPC endpoints (~$21/mo), public-IP SSM path |
| 552b6d0 | 03 ECS cluster & host bootstrap | done — cluster, EC2 capacity provider, launch template, ASG (desired 0), host user-data (vm.max_map_count=262144) |
| 3666126 | 04 PostgreSQL container | done — postgres:17 task def, managed EBS gp3 volume for PGDATA, service, sonar DB + user init |

Milestones M0 (Foundations) and M1 (Network + compute) are **complete**. M2 (Application) is
half done: Slice 04 done, **Slice 05 (SonarQube) is next**.

## What was built (Terraform lives at repo root)

Files: `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `iam.tf`, `secrets.tf`,
`network.tf`, `ecs.tf`, `app.tf`.

Key resource names (all `jra-` prefixed):
- Cluster `jra-sonarqube`; service `jra-sonarqube`; task family `jra-sonarqube` (2 containers — postgres now, SonarQube added in Slice 05).
- Capacity provider `jra-sonarqube-ec2` (EC2 ASG, managed scaling ENABLED, target 100).
- ASG `jra-sonarqube-asg` (min 0 / max 1, `ignore_changes = [desired_capacity]` — ECS managed scaling owns the desired count).
- Host instance profile `jra-ecs-host`; volume role `jra-ecs-volume`.
- Roles: `jra-platform-terraform`, `jra-sonarqube-deploy`, `jra-sonarqube-task`.
- Secrets: `sonarqube/postgres/superuser`, `sonarqube/postgres/app`, `sonarqube/admin` (values out-of-band).

## Local environment / tooling

- Terraform 1.15.8 installed via Homebrew (`hashicorp/tap`).
- AWS CLI v2.36.29 at `~/.local/bin/aws` — add `$HOME/.local/bin` to PATH.
- `~/.aws/config` profiles: `default` (aws login), `terraform` (credential_process shim), `jra-platform-bootstrap` (unused), `jra-platform-terraform` (assumes the Terraform role, source_profile = terraform).
- **Terraform runs as `jra-platform-terraform`** (provider + backend `profile`).
- State: S3 `jra-sonarqube-terraform-state` (key `sonarqube/terraform.tfstate`) + DynamoDB lock `jra-sonarqube-terraform-lock`.
- Secret recovery note (outside repo): `~/jra-sonarqube-secrets-recovery.md`.

## Key decisions made this session (do not reopen)

- **Option 2 networking:** no SSM VPC endpoints; host/task auto-get a public IP (subnet `map_public_ip_on_launch = true`) for outbound SSM + image pulls; inbound blocked by security groups. Free S3 gateway endpoint kept.
- **Host type `m7i-flex.large`** (2 vCPU / 8 GiB, free-tier eligible) instead of `t3.large` (blocked — see Free Tier note). Variable `host_instance_type`; flip back once the restriction is lifted.
- **Two containers in ONE task, ONE service** (awsvpc): SonarQube reaches PostgreSQL via `localhost:5432` (shared network namespace). Slice 04 added postgres; Slice 05 adds SonarQube to the same task.
- **Managed EBS volume** (not rexray/ebs) for PGDATA: `configure_at_launch = true` on the task-def volume + `volume_configuration { managed_ebs_volume { … } }` on the service. (rexray/ebs does not work on the AL2023 ECS AMI.)

## Gotchas / known limitations (important)

1. **EBS volume is delete-on-termination.** ECS replaces the whole task on ANY container stop, and the managed EBS volume is deleted + recreated empty. So "data survives a container restart within the session" (Slice 04 exit #3) does NOT hold. Real durability is S3 backup/restore (Slices 06/07). The AWS provider does not yet expose `termination_policy = "RETAIN"`. Consequences:
   - The **init SQL must be re-run after every task replacement** (creates the `sonar` user + transfers DB ownership; NOT automated yet).
   - Consider automating the init (custom image with `/docker-entrypoint-initdb.d/` script, or `POSTGRES_USER=sonar` native creation) in a later slice.
2. **PostgreSQL container name is auto-generated** (`ecs-jra-sonarqube-<rev>-postgres-<hash>`). Use `docker ps --filter name=postgres --format '{{.ID}}' | head -1`.
3. **ECS managed scaling is slow to scale the ASG up** (minutes). If a task is stuck PENDING, manually set ASG desired to 1.
4. **Managed-scaling draining hook** (`ecs-managed-draining-termination-hook`) holds scale-down in `Terminating:Wait` up to 1 hr. Complete manually: `aws autoscaling complete-lifecycle-action … --lifecycle-action-result CONTINUE`. Slice 08 must handle this.
5. **`assign_public_ip` not supported on EC2 launch type** — do not set it on the service; the subnet handles it.
6. Terraform 1.15 deprecation warnings (cosmetic): `dynamodb_table` (backend) and `inline_policy` (IAM).
7. `aws login` session expires; if a call returns "session expired", re-run `aws login` (needs the human).

## Free Tier account restriction (needs the owner)

The account (`389633344341`) is still in Free Tier mode, which blocks:
- **Launching `t3.large`** → we use `m7i-flex.large` (free-tier eligible, same size).
- **Route 53 domain registration** (`AccessDeniedException: Free Tier accounts are not supported`) → deferred; hosted zone `joericearchitect.com` exists (ID `Z0417046AVLDZS68PD6C`). Owner will use a third-party registrar.

Resolving the Free Tier restriction is the owner's action; not blocking.

## Next: Slice 05 — SonarQube container & service

From `ai-planning/plans/implementation-plans/05-sonarqube-container-and-service.md`:

- **Goal:** run SonarQube Community Build in a second container, exposed only within the private network on port 9000.
- **Steps:**
  1. Add the SonarQube container to the `jra-sonarqube` task definition (pinned Community Build image); mount a second managed EBS volume for `data` (separate from `pgdata`).
  2. Configure the DB connection to PostgreSQL (host `localhost:5432`, `sonar` user/DB) via Secrets Manager.
  3. The service already exists (desired 1); the updated task def will roll out. The app SG already allows 9000 from itself.
  4. Add a health check against `/api/system/status`.
- **Validation:** `/api/system/status` returns UP; the UI is reachable only via an SSM port-forward tunnel, not publicly.

Notes:
- Image `sonarsource/sonarqube` (Community Build). Pin a tested version (never `latest`). Research: 26.2+ supports PostgreSQL 14–18 (we use postgres:17).
- SonarQube needs `vm.max_map_count` (already 262144) + file-descriptor/thread ulimits (already in user-data). Research also cites `>= 524288` for newer ES — reconcile if embedded ES fails to start.
- Inject `SONAR_JDBC_URL`/`SONAR_JDBC_USERNAME`/`SONAR_JDBC_PASSWORD` (and admin password) from Secrets Manager.
- The postgres task will be replaced when the task def changes — **re-run the Slice 04 init SQL afterward** (or automate it first).

## Blocking open questions (unchanged from original)

- **Q5 — backup RPO/schedule/retention/encryption/checksum/restore-validation** → resolve BEFORE Slice 06. Not yet decided.
- Deferred (non-blocking): Q7 (MCP agent integration), Q8 (RDS/ALB migration threshold).

## AWS account context (unchanged)

- Account `389633344341` · region `us-east-1`.
- Auth via `aws login` (console/OAuth); no static keys.
- Roles: `joe-rice-admin` (human, AdministratorAccess) · `jra-platform-terraform` (normal Terraform, least-privilege) · `jra-sonarqube-deploy`/`jra-sonarqube-task`/`jra-ecs-host`/`jra-ecs-volume` (workload).

## Conventions

- Planning docs under `ai-planning/`; Terraform at repo root.
- Secrets and account IDs out of committed source (use `data.aws_caller_identity` + Secrets Manager references).
- Work one slice at a time; commit + push per slice; emit slice + milestone summaries.
