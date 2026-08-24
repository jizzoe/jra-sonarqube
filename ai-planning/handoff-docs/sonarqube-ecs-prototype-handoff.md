# SonarQube ECS Prototype — Implementation Handoff

Date: 2026-08-23
Repo: jra-sonarqube (main @ 057be18, pushed to origin/main)
Purpose: self-contained context for a fresh session to implement all Phase 1 slices.

## Delivery cadence

Follow the milestone/slice delivery cadence defined in:
[sdd-milestone-slice-delivery-skill.md](/Users/joerice/git/joericearchitect/joericearchitect-ai-skills/ai-planning/design-briefs/sdd-milestone-slice-delivery-skill.md)
(repo: `joericearchitect-ai-skills`).

Note: that document is written as a **skill design brief**, but the skill it defines
(`sdd-milestone-slice-delivery`) **does not exist yet**. Apply the workflow **as if it
were a skill** — adopt its cadence (milestone briefing → slice briefing → lifecycle →
slice summary → next-step approval → milestone summary, plus on-demand status queries)
— but **execute implementation based on the implementation plans instead of the SDD
lifecycle**:

- Work one slice at a time, in roadmap order.
- Each `ai-planning/plans/implementation-plans/NN-*.md` is that slice's work spec
  (Goal / Steps / Deliverables / Validation), standing in for Explore/Propose/Apply/
  Verify/Sync/Archive.
- Treat each plan's "Validation (exit criteria)" as that slice's done gate.
- Emit a slice summary after each slice and a milestone summary at milestone
  boundaries, per the cadence.

## What we're building

A cold-off (spun-down-when-idle), single-user SonarQube Community Build on AWS:
SonarQube + PostgreSQL as two containers on one ECS-on-EC2 host, with PostgreSQL
backed up/verified to encrypted S3 and restored on each cold start. Phase 1 has
no public ingress (Session Manager only). Phase 2 (fast follow) exposes
`sonar.joericearchitect.com` over HTTPS.

## Document map

- Design briefs (authoritative):
  - `ai-planning/design-briefs/sonarqube-single-user-ecs-prototype.md` — Phase 1 (primary)
  - `ai-planning/design-briefs/sonarqube-iam-user-bootstrap.md` — IAM model
  - `ai-planning/design-briefs/sonarqube-public-dns-ingress.md` — Phase 2 (fast follow; out of scope now)
- Research (evidence + dated provenance):
  - `ai-planning/research/infrastructure/sonarqube-community-edition-aws-ai-sdd/`
  - `ai-planning/research/infrastructure/sonarqube-aws-cost-and-public-exposure/`
  - `ai-planning/research/infrastructure/sonarqube-iam-user-bootstrap/`
  - `ai-planning/research/infrastructure/sonarqube-public-domain-and-dns/`
- Roadmap: `ai-planning/plans/roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md`
- Implementation plans: `ai-planning/plans/implementation-plans/00-…09-*.md`

## Slice sequence

00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09

- M0 Foundations: 00 (state backend, budget alarm, domain/hosted zone), 01 (IAM roles + Secrets Manager)
- M1 Network+compute: 02 (VPC/SSM), 03 (ECS EC2 cluster + host bootstrap)
- M2 Application: 04 (PostgreSQL), 05 (SonarQube service)
- M3 Durability: 06 (backup + shutdown gate), 07 (restore + reindex)
- M4 Lifecycle+rollout: 08 (orchestration), 09 (cost validation)
- Dependencies: 06/07 need 05; 08 needs 06+07; 09 is the final gate.

## Key decisions (resolved — do not reopen)

- Cold-off lifecycle; PostgreSQL in S3 (not RDS); disposable EBS; no persistent runtime EBS in Phase 1.
- Singleton ECS-on-EC2 capacity provider (never Fargate / ECS Managed Instances); separate SonarQube + PostgreSQL containers.
- No public ingress in Phase 1 (Session Manager only); reserve 443; EIP/DNS/TLS = Phase 2.
- Host `t3.large` (2 vCPU / 8 GiB); on-demand scans; ~15–30 min cold-start budget.
- Budget $33/month (fits $200/6-month credit); budget alarm → joericearchitect@gmail.com.
- DNS: Route 53; hostname `sonar.joericearchitect.com`; domain available (2026-08-23); register domain + hosted zone in Phase 1 (slice 00).
- Secrets in AWS Secrets Manager (values out-of-band; never in state/repo).
- Terraform state backend: S3 + DynamoDB (shared by both phases).
- Product name: "SonarQube Community Build"; main-branch analysis only.

## Blocking open questions (resolve at the indicated slice)

- Q6 — durable secrets location → before slice 01 (default: Secrets Manager + off-repo recovery note).
- Q5 — backup RPO/schedule/retention/encryption/checksum/restore-validation → before slice 06.
- Deferred (non-blocking): Q7 (MCP agent integration), Q8 (RDS/ALB migration threshold).

## AWS account context

- Account ID: 389633344341 · Region: us-east-1
- AWS CLI v2.36.29 at ~/.local/bin/aws (add $HOME/.local/bin to PATH). Auth via `aws login` (console/OAuth), not static keys.
- Profiles (~/.aws/config):
  - `default` → login session as `joe-rice-admin`
  - `jra-platform-bootstrap` → role_arn = arn:aws:iam::389633344341:role/jra-platform-bootstrap, source_profile = default
- Session expiry: if a call returns "Your session has expired", re-run `aws login`.
- Current IAM state:
  - `joe-rice-admin`: console access, MFA (U2F), no access keys; direct policies `IAMUserChangePassword` + `SignInLocalDevelopmentAccess`; member of `jra-admin`.
  - `jra-admin` group: `AdministratorAccess`.
  - `jra-platform-bootstrap` role: trusted by `joe-rice-admin` only; no policies attached (empty shell pending least-privilege design).
  - Not yet created (slice 01): `jra-platform-terraform`, `jra-sonarqube-deploy`, `jra-sonarqube-task`.
  - Root: MFA enabled, no access keys. Account aliases: none.

## Conventions

- Planning docs live under `ai-planning/`; Terraform implementation will live at repo root (to be created).
- Re-confirm AWS rates in the Pricing Calculator immediately before implementation (research figures are dated).
- Keep secrets and account IDs out of committed Terraform state/source; use variables + Secrets Manager references.
