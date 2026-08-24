# Slice 08 — Lifecycle orchestration — slice summary

Status: ✅ complete (2026-08-24)

## Goal

Wrap the backup/restore/teardown pieces into idempotent `start` and `cold-stop`
workflows with health checks.

## Deliverables

- `scripts/lib.sh` — shared config + helpers (host/task discovery, SSM
  `send-command`/wait, `run_on_host` base64 transport, `sonar_api`,
  admin-password candidates).
- `scripts/start.sh` — cold start: `terraform apply` → nudge ASG → wait host →
  wait task RUNNING → `restore.sh` → force-new-deployment (reindex) → health
  gate → write `metadata/restored.txt`. Resumable + idempotent (marker-based).
- `scripts/cold-stop.sh` — CE drain → `backup-and-verify.sh` →
  `teardown-guard.sh` → service desired-count 0 → ASG 0 + complete
  `ecs-managed-draining-termination-hook` → verify termination.
- `scripts/status.sh` — `status` / `health` / `logs [sonarqube|postgres]`.
- `Makefile` — `start` / `cold-stop` / `status` / `health` / `logs`.
- `docs/runbooks/start-stop-recover.md` — start / stop / recover runbook.
- `iam.tf` — `ssm:SendCommand` (+ read/invocation) for `jra-platform-terraform`.

## Validation (exit criteria)

Two consecutive full start → stop cycles succeeded against real AWS:
`cold-stop` (reset) → `start` → `cold-stop` → `start` → `cold-stop`, ending
cold-off (ASG desired 0, no instances, no EBS). SonarQube reached `UP` on both
starts; dumps verified on both stops.

## Bugs found & fixed during live validation

1. **SSM `SendCommand` document ARN** — AWS-owned docs use an empty owner
   (`arn:aws:ssm:us-east-1::document/AWS-RunShellScript`), not the account ID.
2. **Transient IAM AccessDenied + non-resumable start** — added retry
   (5×20s) to `run_on_host` and made `start` resumable via an S3 marker.
3. **CE drain auth** — `/api/ce/activity_status` requires auth; added fallback
   from the secret to SonarQube's default `admin` (override via
   `SONAR_ADMIN_PASSWORD`).

## Commits

`84da1ff`, `03f13bf`, `1d576fc`, `f87f775` (pushed to `origin/main`).

## Known notes (non-blocking)

- The `sonarqube/admin` secret is not injected into the container, so the
  SonarQube admin password is still the out-of-box `admin`.
