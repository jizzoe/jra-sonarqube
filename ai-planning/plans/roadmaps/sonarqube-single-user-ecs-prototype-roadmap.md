# SonarQube single-user ECS prototype — implementation roadmap

## Purpose

Iterative, sliced plan for implementing [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md) (Phase 1). Each slice has a companion plan in [../implementation-plans](../implementation-plans).

## Scope boundary

- **In scope (Phase 1):** cold-off ECS-on-EC2 singleton running SonarQube Community Build + PostgreSQL, disposable EBS volumes, encrypted S3 backup/restore, Session Manager access only, a $33/month budget alarm, and the Route 53 domain + hosted zone registered as preparation for Phase 2.
- **Out of scope (Phase 2, fast follow):** public ingress — Elastic IP, DNS `A` record, TLS, inbound 443. See [sonarqube-public-dns-ingress.md](../../design-briefs/sonarqube-public-dns-ingress.md).
- **Deferred:** read-only MCP agent integration (Q7), RDS/ALB migration (Q8).

## Principles

- **Cold off by default:** no compute, EBS, or public IP while idle; the only persistent costs are S3, the domain, and the hosted zone.
- **Cost ceiling:** stay under $33/month via cold-off; a budget alarm guards the $200/6-month credit.
- **Least privilege + secrets out of state:** separate task/deploy roles; credentials in Secrets Manager, never in Terraform state or the repository.
- **No public ports in Phase 1:** administration only via Systems Manager Session Manager.

## Milestones and slices

| # | Milestone | Slices | Outcome |
| --- | --- | --- | --- |
| M0 | Foundations | 00 account foundations · 01 IAM roles & secrets | State backend, budget alarm, domain/hosted zone, workload roles |
| M1 | Network + compute | 02 VPC & access · 03 ECS EC2 cluster & host bootstrap | Private network + capacity provider with host prerequisites |
| M2 | Application | 04 PostgreSQL · 05 SonarQube service | Two-container app reachable internally over 9000 |
| M3 | Durability | 06 backup & shutdown gate · 07 restore & reindex | Verified S3 dumps + tested restore path |
| M4 | Lifecycle & rollout | 08 orchestration · 09 cost validation | Repeatable cold-start/cold-stop + budget proof |

## Sequencing

```text
00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09
```

- 06 and 07 depend on 05 (a running application to back up and restore).
- 08 depends on 06 + 07 (both directions of the lifecycle).
- 09 is the final full-cycle gate; nothing ships until it passes.

## Blocking open questions

Resolve before the indicated slice:

- **Q6 — durable secrets location** → before slice 01 (default: AWS Secrets Manager + an off-repo recovery note).
- **Q5 — backup RPO/schedule/retention/encryption/checksum/restore-validation** → before slice 06.
- Q7 (agent/MCP) and Q8 (RDS/ALB threshold) are deferred and do not block Phase 1.

## Definition of done

- A cold start provisions the host, restores PostgreSQL from S3, and brings SonarQube healthy in ~15–30 minutes.
- A cold stop blocks work, dumps and verifies the database in S3, then destroys EC2/EBS (no idle charges).
- The budget alarm fires on the $33/month trajectory; the cold-off floor is confirmed at ~S3 + domain + hosted zone.
