# SonarQube single-user ECS prototype design brief

## 1. Problem and desired outcome

Create infrastructure as code for an inexpensive, single-user SonarQube Community Build deployment on AWS. It must retain a Dockerized ECS deployment model while avoiding all material idle runtime cost.

The selected operating model is **cold off**: SonarQube Community Build and PostgreSQL run as separate containers on one ECS EC2 host only during a working session. PostgreSQL is not Amazon RDS. Before shutdown, the database is backed up and verified in S3; then ECS/EC2 capacity and EBS working volumes are destroyed (and, in Phase 2, the Elastic IP is released). A future cold start rebuilds the host and restores PostgreSQL from S3.

## 2. Evidence and key findings

This brief is based on durable research:

- [SonarQube Community Build, AWS, AI, and SDD findings](../research/infrastructure/sonarqube-community-edition-aws-ai-sdd/sonarqube-community-edition-aws-ai-sdd-findings.md)
- [AWS cost and public-exposure findings](../research/infrastructure/sonarqube-aws-cost-and-public-exposure/sonarqube-aws-cost-and-public-exposure-findings.md)
- [Repository README](../../README.md)

Key findings:

- ECS on EC2 capacity has no material ECS control-plane fee beyond the underlying host. Fargate is unsuitable because SonarQube's embedded Elasticsearch host settings cannot be supported there.
- The PostgreSQL database is the durable source of truth. SonarQube must rebuild Elasticsearch after restoration; Elasticsearch data is not restored from backup.
- Colocating PostgreSQL avoids the researched RDS baseline, but the application and database share one working-host failure domain.
- Stopping a task alone does not remove EC2 cost. EBS, public IPv4/EIP, and S3 can also persist charges unless deliberately retained or deleted.
- Community Build supports main-branch analysis only. AI-agent access should be local, read-only, and use a dedicated non-admin SonarQube identity.

## 3. Options considered and tradeoffs

| Option | Impact and tradeoff |
| --- | --- |
| Always-on singleton ECS EC2 host with colocated PostgreSQL | Fastest access, but creates continuous compute and storage charges. Rejected for the initial cost target. |
| Paused host: scale tasks/host down but retain EBS and Elastic IP | Stops compute cost but retains storage and public-IP charges. Better for frequent short gaps, but not the chosen default. |
| **Cold-off singleton ECS EC2 host with S3 database restore** | **Recommended.** Destroys ECS/EC2 and EBS after each verified backup (and, in Phase 2, releases the public IP). Retains only S3 backup/state and the DNS zone. Startup is slower and recovery point is the latest verified backup. |
| ECS EC2 with PostgreSQL on RDS | Better database isolation, but recurring RDS cost conflicts with the initial target. |
| ECS Fargate | Rejected: unsupported for SonarQube's Elasticsearch prerequisites. |
| Internet-facing ALB with ACM | Production-aligned ingress but adds meaningful fixed cost. Defer. |
| On-demand Elastic IP, DNS, and local TLS proxy | Recommended **Phase 2** ingress (fast follow). Terraform allocates an IP and updates DNS at startup, then releases the IP at cold shutdown; address changes and DNS/TLS readiness add startup time. |

## 4. Decisions, assumptions, and owner

- Owner: repository owner.
- User-stated decision: use the cold-off lifecycle with PostgreSQL backups in S3 and restore from S3 whenever the service is started.
- Decision: use a singleton ECS-on-EC2 capacity provider. SonarQube Community Build and PostgreSQL run as separate containers on one x86 host. Do not provision RDS, ALB, NAT gateway, or persistent runtime EBS in phase 1.
- Decision: on cold start, provision a fresh host and disposable EBS working volumes; restore the newest verified PostgreSQL dump; then start SonarQube with an empty Elasticsearch directory so it reindexes.
- Decision: before cold shutdown, block new work, wait for active analysis to finish, create a PostgreSQL logical dump, upload it to encrypted S3 with a checksum and restore metadata, verify it, and only then destroy runtime resources.
- Decision: use an on-demand Elastic IP, Terraform-managed DNS A record, and local TLS reverse proxy. Release the IP during cold shutdown.
- Decision: budget cap of $33/month with a budget alarm notifying joericearchitect@gmail.com. The cap is sized to stay within a $200/6-month credit; the cold-off lifecycle is the primary cost control.
- Decision: DNS provider is Amazon Route 53; the public hostname is `sonar.joericearchitect.com` (`joericearchitect.com` confirmed available for registration on 2026-08-23). Public exposure is a fast-follow add-on (see the public DNS/ingress brief); phase 1 registers the apex domain and creates the hosted zone but does not yet publish the public `A` record.
- Decision: HTTPS is publicly available (no fixed-IP/VPN allowlist). SonarQube's own authentication is therefore the security boundary: a strong admin password and a dedicated non-admin scan identity are required.
- Decision: default host size is `t3.large` (2 vCPU / 8 GiB); scans run on demand during a working session; the accepted cold-start budget is ~15–30 minutes.
- Assumptions: one user, infrequent on-demand scans, and a 15–30 minute cold-start window is acceptable; trusted HTTPS requires a user-owned hostname. The account has a $200/6-month credit budget, so the hard ceiling is $33/month; cold-off destruction is the primary cost control.
- Formal approval evidence: no digest-bound confirmation was supplied. The recorded decision captures the user's direction and should be formally confirmed before AWS-account changes begin.

## 5. Scope, non-goals, constraints, dependencies, and risks

### Scope

- Terraform for an x86 ECS EC2 capacity provider and singleton service whose runtime resources can be created and destroyed as a unit.
- Separate pinned SonarQube Community Build and PostgreSQL containers, with host Elasticsearch prerequisites applied at boot.
- Fresh, disposable EBS working volumes on each start; encrypted S3 logical PostgreSQL dumps, checksums, retention, and tested restore metadata.
- Least-privilege workload roles and secrets outside Terraform state. (Public ingress — Elastic IP, DNS `A` record, and TLS — is Phase 2; see the public DNS/ingress brief.)
- Explicit `start`, `backup-and-verify`, and `cold-stop` workflows, health checks, minimal logs, budget alerts, and a tested restore/reindex path.
- Optional local, read-only SonarQube MCP integration after CI scanning works.

### Non-goals

- RDS, Multi-AZ, high availability, automatic horizontal scaling, persistent runtime storage, ALB, WAF, NAT gateway, or a production SLA.
- Multiple users, paid SonarQube features, PR or multi-branch analysis unavailable in Community Build, or a shared remote MCP service.
- A guarantee of zero charges: S3 backup/state, DNS/domain, and limited logs may retain small costs.

### Constraints and dependencies

- Use ECS on EC2 capacity, never Fargate or ECS Managed Instances.
- Apply `vm.max_map_count`, file-descriptor/process limits, and supported x86 runtime settings at host boot before tasks start.
- Do not expose SonarQube port 9000, PostgreSQL, Elasticsearch, SSH, Docker, or ECS-agent ports. Use Systems Manager Session Manager for administration.
- (Phase 2) Terraform must control the DNS A record and update it when each cold start allocates a new public IP.
- Durable bootstrap configuration and SonarQube secrets must be recoverable separately from the database dump and must never enter Terraform state or the repository.
- A shutdown is permitted only after S3 object existence, checksum, and metadata verification succeeds.
- Register the apex domain `joericearchitect.com` and create the Route 53 public hosted zone in phase 1 (the persistent low-cost layer), so the later public DNS/ingress add-on only adds the public `A` record and TLS.
- Use a shared S3 + DynamoDB Terraform state backend for both phase 1 and the later public-ingress add-on.
- Reserve inbound port 443 for the phase 2 public-ingress add-on; phase 1 exposes no public ports and is reached only via Systems Manager Session Manager.

### Architecture and lifecycle

```text
Persistent, low-cost layer
  encrypted S3 PostgreSQL dumps + checksum + restore metadata
  Terraform state + DNS zone/record management + secure secret source
                         |
                     cold start
                         v
  Terraform -> ECS EC2 host -> PostgreSQL restore -> SonarQube reindex
                         |
       (Phase 2) DNS hostname -> on-demand Elastic IP :443 -> local TLS proxy
                         |
                    working session
                         |
  verify DB dump in S3 -> destroy ECS/EC2 + EBS (+ release Elastic IP in Phase 2) -> cold off
```

### Risks

- The most recent verified backup defines the recovery point. Data generated after it can be lost; a failed backup or upload must prevent destruction.
- Cold start requires host bootstrap, database restoration, and SonarQube reindexing (plus DNS update/TLS readiness in Phase 2). The service is not instantly available.
- (Phase 2) The public IP can change every session; the DNS, certificate, proxy, and security-group workflow must be automated and tested.
- An 8 GiB host may be insufficient for larger scans; T3 CPU credits can add cost while the host runs.
- Losing durable configuration or encryption/JWT secrets can make a restore incomplete or invalidate encrypted settings even when the database dump is valid.

## 6. Open questions and blocking decisions

1. ~~Budget cap + notification e-mail~~ — **Resolved: $33/month cap; alarm to joericearchitect@gmail.com.**
2. ~~Hostname and DNS provider~~ — **Resolved: Route 53, `sonar.joericearchitect.com`; public exposure is a fast-follow add-on.**
3. ~~HTTPS access restriction~~ — **Resolved: publicly available (no IP allowlist).**
4. ~~Scan cadence, repository size, cold-start time, host size~~ — **Resolved: `t3.large`, on-demand scans, small-to-medium repos (< ~500K LOC aggregate), ~15–30 min cold start.**
5. What recovery point objective, backup schedule, S3 retention, encryption/key-management policy, checksum format, and restore validation are acceptable?
6. Where will durable runtime configuration and SonarQube secrets be stored and recovered without entering source control or Terraform state?
7. Will agent integration start as the official local read-only MCP server, SonarQube Web API only, or be deferred?
8. What threshold—cost, scan duration, recovery need, or user count—triggers migration to RDS and ALB/ACM?

## 7. Recommended next step

Budget, hostname, HTTPS, and sizing are resolved; the remaining open questions are secret recovery (Q6) and backup retention (Q5). Implementation is sequenced in the [roadmap](../../plans/roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md); the IP/DNS lifecycle is deferred to the Phase 2 public DNS/ingress brief. No OpenSpec artifacts were created by this brief.
artifacts were created by this brief.
