# SonarQube ECS Prototype — Handoff (Slice 08 onward)

Date: 2026-08-24
Repo: jra-sonarqube (main @ bcd628a, pushed to origin/main)
Purpose: self-contained context for a fresh session to continue from the end of Slice 07 into Slice 08 (orchestration) and Slice 09 (cost validation).

## Delivery cadence

Unchanged: work one slice at a time in roadmap order; each `ai-planning/plans/implementation-plans/NN-*.md` is the work spec (Goal / Steps / Deliverables / Validation); treat "Validation (exit criteria)" as the done gate; emit a slice summary per slice + a milestone summary at boundaries. The referenced cadence brief is `sdd-milestone-slice-delivery-skill.md` in repo `joericearchitect-ai-skills`.

## Progress so far (all pushed to origin/main)

| Commit | Slice | Status |
| --- | --- | --- |
| 4db241c | 00 Account foundations | done |
| 4f07527 | 01 IAM roles & secrets (Q6) | done |
| 675ba23 | 02 VPC & access | done |
| 4673777 | Option 2 (drop SSM endpoints) | done |
| 552b6d0 | 03 ECS cluster & host bootstrap | done |
| 3666126 | 04 PostgreSQL container | done |
| 5aa9ffa + 1fb4aba | 05 SonarQube container & service | done |
| 4814bf1 | 06 Backup & shutdown gate (Q5, Option A) | done |
| bcd628a | 07 Restore & reindex | done |

Milestones **M0, M1, M2, M3 are all complete**. **7 of 10 slices done (70%)**.
Remaining: **Slice 08 (Lifecycle orchestration)** and **Slice 09 (Cost validation & rollout)**.

## What's built (Terraform at repo root + scripts/)

Terraform files: `providers.tf`, `variables.tf`, `main.tf` (00), `outputs.tf`, `iam.tf` (roles/policies), `secrets.tf`, `network.tf` (VPC/SGs/endpoints), `ecs.tf` (cluster/capacity provider/launch template/ASG/host role), `app.tf` (task def + service + volume role), `backup.tf` (S3 dumps bucket + host S3 policy).

Scripts (all run on the HOST, via SSM or the future orchestration):
- `scripts/backup-and-verify.sh` — `pg_dump -Fc` → SHA-256 → `aws s3 cp` (checksum as metadata) → verify → write `s3://jra-sonarqube-dumps/metadata/latest.txt` (`<key> <sha256>`).
- `scripts/restore.sh` — read `latest.txt` → download → SHA-256 verify → `pg_restore --clean --if-exists -U sonar -d sonar` → `rm -rf /var/lib/sonarqube-data/es8` (forces reindex).
- `scripts/teardown-guard.sh` — rejects teardown unless a verified dump exists (compares `latest.txt` checksum to the S3 object metadata).

Key names (all `jra-` prefixed): cluster `jra-sonarqube`, service `jra-sonarqube`, task family `jra-sonarqube` (2 containers: postgres + sonarqube, awsvpc, one task), capacity provider `jra-sonarqube-ec2`, ASG `jra-sonarqube-asg` (min 0 / max 1, `ignore_changes = [desired_capacity]`), state bucket `jra-sonarqube-terraform-state`, dumps bucket `jra-sonarqube-dumps`, lock table `jra-sonarqube-terraform-lock`.

## Local environment / tooling

- Terraform 1.15.8 (Homebrew `hashicorp/tap`).
- AWS CLI v2.36.29 at `~/.local/bin/aws` (add `$HOME/.local/bin` to PATH).
- `~/.aws/config` profiles: `default` (aws login), `terraform` (credential_process shim), `jra-platform-bootstrap` (unused), `jra-platform-terraform` (assumes the Terraform role, `source_profile = terraform`).
- **Terraform runs as `jra-platform-terraform`** (provider + backend `profile`).
- Secrets recovery note (outside repo): `~/jra-sonarqube-secrets-recovery.md`.

## Key decisions (do not reopen)

- **Option 2 networking:** no SSM VPC endpoints; host/task auto-get a public IP (subnet `map_public_ip_on_launch = true`) for outbound SSM + image pulls; inbound blocked by SGs. Free S3 gateway endpoint kept.
- **Host type `m7i-flex.large`** (2 vCPU / 8 GiB, free-tier eligible) instead of `t3.large` (blocked). Variable `host_instance_type`.
- **Two containers in ONE task, ONE service** (awsvpc): SonarQube → PostgreSQL via `localhost:5432`. Singleton deploy (`deployment_minimum_healthy_percent = 0`, `maximum = 100`) so the 2-vCPU task can't overlap.
- **Host-path bind mounts for BOTH pgdata and sonarqube data** (`/var/lib/postgresql-data`, `/var/lib/sonarqube-data`) — NOT managed EBS. Reason: managed EBS is delete-on-termination, which wipes data on task replacement (broke the restore→reindex sequence). Host-path survives task replacement within a session and is destroyed on cold stop (correct cold-off model).
- **Backup policy (Q5) = Option A:** `pg_dump -Fc` at each cold stop, SHA-256 checksum as S3 metadata, SSE-S3, 90-day S3 lifecycle on the `sonar-` prefix, restore validated on each cold start.
- **`POSTGRES_USER=sonar`** (native user/DB creation) so the DB user is recreated on every fresh volume — no manual init, no crash loop.

## Gotchas / known limitations (important for Slice 08)

1. **Data survives task replacement via host-path, not EBS.** The `jra-ecs-volume` IAM role is now unused (leftover from the managed-EBS approach).
2. **ECS managed scaling is slow to scale the ASG up.** If a task is stuck PENDING, manually: `aws autoscaling update-auto-scaling-group --auto-scaling-group-name jra-sonarqube-asg --desired-capacity 1`.
3. **Managed-scaling draining hook** (`ecs-managed-draining-termination-hook`) holds scale-down in `Terminating:Wait` up to 1 hr. Complete manually: `aws autoscaling complete-lifecycle-action --auto-scaling-group-name jra-sonarqube-asg --lifecycle-hook-name ecs-managed-draining-termination-hook --instance-id <id> --lifecycle-action-result CONTINUE`. **Slice 08's cold-stop MUST handle this** for a clean teardown.
4. **`assign_public_ip` is not supported on EC2 launch type** — don't set it on the service.
5. **PostgreSQL container name is auto-generated** (`ecs-jra-sonarqube-<rev>-postgres-<hash>`). Use `docker ps --filter name=postgres --format '{{.ID}}' | head -1`.
6. **Free Tier account** blocks `t3.large` and Route 53 domain registration. We use `m7i-flex.large`; domain registration deferred (owner will use a third-party registrar). Hosted zone `joericearchitect.com` exists (ID `Z0417046AVLDZS68PD6C`).
7. **Terraform 1.15 deprecation warnings** (cosmetic): `dynamodb_table` (backend) and `inline_policy` (IAM).
8. **`aws login` session expires**; if "session expired", re-run `aws login` (human-only).
9. **The `sonarqube/postgres/superuser` secret is now unused** (the `sonar` user is a superuser using the app secret).
10. The slice-07 end-to-end restore test created a test project `slice07_test` in the current DB; the latest dump contains it.

## Next: Slice 08 — Lifecycle orchestration

From `ai-planning/plans/implementation-plans/08-lifecycle-orchestration.md`:

- **Goal:** wrap the pieces into idempotent `start` and `cold-stop` workflows with health checks.
- **Steps:**
  1. `start`: `terraform apply` (network/cluster/task/service) → restore (slice 07) → reindex → health gate.
  2. `cold-stop`: block new scans → wait for in-flight analysis → `backup-and-verify` (slice 06) → `terraform destroy` of EC2/EBS (release public IP in Phase 2).
  3. Status/health check + minimal CloudWatch Logs.
  4. Document runbooks (start / stop / recover).
- **Deliverables:** `start` and `cold-stop` orchestration (scripts or Makefile), health check, runbook.
- **Validation:** two consecutive full start → stop → start cycles succeed with no manual steps.

Notes for Slice 08:
- Keep orchestration as scripts over `terraform apply`/`aws` (don't embed lifecycle logic in state).
- The host auto-scales up when the service needs a task (managed scaling), but the cold-stop MUST complete the draining hook (gotcha #3) and delete the host-path data dirs (or destroy the host).
- The cold-start sequence the scripts already support: host up → restore (`restore.sh`) → force new deployment (SonarQube reindex) → health gate. Wrap it.
- The teardown guard (`teardown-guard.sh`) is the "block teardown without a valid dump" gate to call before destroy.
- Slice 09 (cost) will prove the cold-off floor; remember `m7i-flex.large` ~ $0.08/hr if left on 24/7, so cold-off is the control.

## Open questions

- **Q7** (MCP agent integration) and **Q8** (RDS/ALB migration threshold) — deferred, non-blocking.
- Q5 resolved (Option A) · Q6 resolved (Secrets Manager).

## AWS account context (unchanged)

- Account `389633344341` · region `us-east-1`. Auth via `aws login` (no static keys).
- Roles: `joe-rice-admin` (human, admin) · `jra-platform-terraform` (Terraform, least-privilege) · `jra-sonarqube-deploy`/`jra-sonarqube-task`/`jra-ecs-host`/`jra-ecs-volume`(unused now) (workload).

## Conventions

- Planning docs under `ai-planning/`; Terraform at repo root; scripts under `scripts/`.
- Secrets and account IDs out of committed source.
- One slice at a time; commit + push per slice; slice + milestone summaries.
