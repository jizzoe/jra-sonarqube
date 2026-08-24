# SonarQube ECS Prototype — Handoff (Phase 2)

Date: 2026-08-24 · Repo: jra-sonarqube (main, pushed to origin/main)

## Phase 1 status: COMPLETE

Slices 00–09 done; milestones M0–M4 complete. A cold-off SonarQube Community
Build singleton on ECS/EC2, with verified backup/restore, teardown guard, and
`make start` / `make cold-stop` orchestration. Budget proof: cold-off floor
≈ $0.51/month, representative month ≈ $2.31/month (cap $33).

## Next: Phase 2 — public DNS/ingress

Brief: `ai-planning/design-briefs/sonarqube-public-dns-ingress.md`

- Expose the UI at `https://sonar.joericearchitect.com` over 443.
- Model: on-demand Elastic IP + Terraform-managed DNS `A` record + host TLS
  proxy; release the EIP on cold stop (preserves the cold-off floor).
- **Open question (blocking):** TLS method — Let's Encrypt (free, DNS-01
  automation) vs ACM exportable cert ($7.00/FQDN). Also re-confirm the ALB+ACM
  migration threshold (Q8).

## Key facts for the next session

- Account `389633344341` · region `us-east-1`. Auth via `aws login` (no static
  keys). Terraform runs as profile `jra-platform-terraform`.
- Hosted zone `joericearchitect.com` (ID `Z0417046AVLDZS68PD6C`).
- Names: cluster/service/task family `jra-sonarqube`; ASG `jra-sonarqube-asg`
  (min 0/max 1); dumps bucket `jra-sonarqube-dumps`; state bucket
  `jra-sonarqube-terraform-state`.
- Free Tier blocks `t3.large` and Route 53 domain registration → we use
  `m7i-flex.large`; domain registration via third-party registrar.
- Orchestration: `make start` / `cold-stop` / `status` / `health` / `logs`
  (scripts under `scripts/`). Runbooks under `docs/runbooks/`.
- The `sonarqube/admin` secret is not wired into the container (admin password
  is still the default `admin`); consider fixing during Phase 2.

## Conventions

Planning docs under `ai-planning/`; Terraform at repo root; scripts under
`scripts/`; secrets/account IDs out of committed source. One slice at a time;
commit + push per slice; slice + milestone summaries under
`ai-planning/summaries/`.
