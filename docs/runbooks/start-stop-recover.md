# SonarQube ECS — Runbook: start / stop / recover

Cold-off operating model: nothing runs while idle. A working session is a
bounded `start` → (use) → `cold-stop` cycle. The only durable data between
sessions is the verified PostgreSQL dump in S3 plus Terraform state.

## Prerequisites

- AWS auth is fresh: `aws login` (human-only; a "session expired" error means
  re-run it).
- Terraform is installed and `AWS_PROFILE`/`~/.aws/config` has the
  `jra-platform-terraform` profile (see `providers.tf`).
- The Terraform backend has been initialized once (`terraform init`); `start`
  runs it automatically if `.terraform/` is missing.

All orchestration runs from the repo root and uses the least-privilege
`jra-platform-terraform` profile (override with `AWS_PROFILE=…`).

## Start (cold start)

```bash
make start            # or ./scripts/start.sh
```

What it does (idempotent — a second run with a host already up is a no-op):

1. `terraform apply` — converges network/cluster/task/service (+ host SG 443,
   host Route 53 DNS-01 policy, Caddy installed via user-data).
2. Nudges the ASG to `desired_capacity 1` (ECS managed scaling is slow to scale up).
3. Waits for the host instance to be SSM-managed and the task to reach RUNNING.
4. Runs `scripts/restore.sh` on the host — downloads the newest verified dump,
   verifies SHA-256, `pg_restore --clean --if-exists`, clears
   `/var/lib/sonarqube-data/es8`.
5. `ecs update-service --force-new-deployment` — SonarQube restarts and reindexes.
6. Health gate — polls `/api/system/status` until `UP` (up to ~25 min).
7. Allocates an Elastic IP and associates it to the host (or reuses one already
   attached).
8. UPSERTs the `sonar.joericearchitect.com` A record to the EIP, then starts the
   Caddy TLS proxy (restoring the cached cert from S3 first).

Expected duration: ~15–30 minutes (image pull + restore + reindex); the first
TLS issuance adds a minute or two.

## Stop (cold stop)

```bash
make cold-stop       # or ./scripts/cold-stop.sh
```

What it does (idempotent — a second run with no host is a no-op):

1. Blocks new scans and waits for in-flight Compute Engine analysis to drain
   (`/api/ce/activity_status` until `pending=0` and `inProgress=0`).
2. Runs `scripts/backup-and-verify.sh` — `pg_dump -Fc` → SHA-256 → `s3 cp` →
   verify → write `s3://jra-sonarqube-dumps/metadata/latest.txt`.
3. Runs `scripts/teardown-guard.sh` — refuses to continue unless a verified
   dump exists.
4. Stops the Caddy TLS proxy and uploads its cert cache to
   `s3://jra-sonarqube-dumps/caddy/data.tar.gz` (so the next start reuses the
   cert and avoids re-issuing).
5. Releases the Elastic IP and deletes the `sonar.joericearchitect.com` A record.
6. Scales the service to `desired_count 0` (stops the task).
7. Scales the ASG to `desired_capacity 0` and completes the ECS
   `ecs-managed-draining-termination-hook` so the instance actually terminates
   (EBS is `delete_on_termination`, so data volumes are destroyed).
8. Verifies the instance is terminated.

After a cold stop the only costs are S3, the domain, and the hosted zone.

## Status / health / logs

```bash
make status          # host, task, service counts, latest backup, health
make health          # exit 0 if SonarQube is UP, 1 otherwise (health gate)
make logs            # tail the latest SonarQube log stream
make logs PREFIX=postgres   # tail the latest postgres log stream
```

Logs stream to CloudWatch Logs group `/ecs/jra-sonarqube` (streams
`sonarqube/…` and `postgres/…`, configured by the task definition).

## Reaching the SonarQube UI

Public HTTPS (Phase 2): `https://sonar.joericearchitect.com` — the Caddy TLS
proxy on the host terminates 443 and forwards to SonarQube's 9000. This requires
the domain to be registered and its name servers delegated to the Route 53
hosted zone; until then the A record won't resolve and certificate issuance will
fail (Caddy keeps retrying in the background).

Admin fallback (SSM, always available):

- Interactive shell: `aws ssm start-session --target <host-id>`.
- API check from the host: `curl http://<task-ip>:9000/api/system/status`
  (task IP from `make status`).
- Browser UI via port-forward to the host's localhost HTTP bridge (Caddy serves
  `http://127.0.0.1:8080` and reverse-proxies to SonarQube's 9000):

```bash
aws ssm start-session \
  --target <host-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

then open `http://localhost:8080`. (The tunnel lands on the host's
`127.0.0.1:8080`, which Caddy reverse-proxies to the task.)

## Admin password

- Default credentials are `admin` / `admin`.
- The `sonarqube/admin` secret is injected as `SONAR_ADMIN_PASSWORD`, but
  SonarQube only reads it on a **fresh install** (first boot against an empty
  database). The normal cold-start restores the S3 dump, which overwrites the
  admin user — so the password that actually wins is whatever was last saved in
  the dump.
- To change the password: **My Account → Security** in the UI. It is captured
  by the next `cold-stop` backup and restored on every future `cold-start`.
- If you change it in the UI, the `sonarqube/admin` secret becomes stale (it is
  only consulted for a hypothetical future fresh install). Sync it:
  `aws secretsmanager put-secret-value --secret-id sonarqube/admin --secret-string '<password>'`.

## Recover

| Symptom | Action |
| --- | --- |
| Task stuck `PENDING` after start | `aws autoscaling update-auto-scaling-group --auto-scaling-group-name jra-sonarqube-asg --desired-capacity 1` |
| Host stuck in `Terminating:Wait` on stop | `aws autoscaling complete-lifecycle-action --auto-scaling-group-name jra-sonarqube-asg --lifecycle-hook-name ecs-managed-draining-termination-hook --instance-id <id> --lifecycle-action-result CONTINUE` |
| `cold-stop` refuses to teardown | A verified dump is missing — check `s3://jra-sonarqube-dumps/metadata/latest.txt`; re-run the backup step. |
| "session expired" | Re-run `aws login` (human-only). |
| Corrupt/lost DB | Start from the newest verified dump: re-run `make start` (restore always uses `metadata/latest.txt`). |
| Secrets lost | See the off-repo note `~/jra-sonarqube-secrets-recovery.md`; secrets never enter the repo or state. |
| `start` refuses because a host is up | The session is already running; `make cold-stop` then `make start` for a clean restart. |

## Conventions

- Work one slice at a time; commit + push per slice.
- Secrets and account IDs stay out of committed source.
- Terraform at repo root; scripts under `scripts/`; runbooks under `docs/runbooks/`.
