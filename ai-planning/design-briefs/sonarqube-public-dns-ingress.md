# SonarQube public DNS/ingress design brief (Phase 2 add-on)

> This is a **later add-on** to [sonarqube-single-user-ecs-prototype.md](sonarqube-single-user-ecs-prototype.md).
> Phase 1 implements the prototype and registers the apex domain + Route 53 hosted zone, but exposes no public ingress (access via Systems Manager Session Manager only). This brief adds the public DNS record, TLS, and 443 exposure.
> This brief is applied only after Phase 1 is working, to expose the UI at `https://sonar.joericearchitect.com`.

## 1. Problem and desired outcome

After the cold-off ECS prototype is operational, expose the SonarQube Community Build UI at a friendly, stable hostname — `sonar.joericearchitect.com` — over HTTPS, while preserving the cold-off lifecycle and its cost floor.

The selected operating model keeps the prototype's "on-demand Elastic IP + local TLS proxy" ingress: Terraform allocates a public IP and updates the DNS `A` record on each cold start, then releases the IP on shutdown. Only the domain registration and the Route 53 hosted zone persist.

## 2. Evidence and key findings

This brief is based on durable research:

- [Public domain and DNS findings](../research/infrastructure/sonarqube-public-domain-and-dns/sonarqube-public-domain-and-dns-findings.md)
- [AWS cost and public-exposure findings](../research/infrastructure/sonarqube-aws-cost-and-public-exposure/sonarqube-aws-cost-and-public-exposure-findings.md)
- [SonarQube single-user ECS prototype design brief](sonarqube-single-user-ecs-prototype.md)

Key findings:

- Exposing the UI needs a registered apex domain, a Route 53 hosted zone with an `A` record, a TLS certificate, and a public ingress path.
- The cold floor is a domain registration (~$14/year) plus the hosted zone (~$0.50/month); releasing the Elastic IP and destroying any ALB drive the rest to $0.
- ACM public certificates are free but cannot be installed on EC2; the host-level proxy must use Let's Encrypt (free) or an ACM exportable certificate ($7.00/FQDN per issuance/renewal).
- The Elastic IP changes on every session, so the DNS `A` record and the TLS certificate must be updated and verified on each cold start.

## 3. Options considered and tradeoffs

| Option | Impact and tradeoff |
| --- | --- |
| **Elastic IP + local TLS proxy (Let's Encrypt)** | **Recommended default.** Matches the prototype's cold-off cost target; free cert; requires DNS-01 automation and renewal; IP churn adds DNS/TLS startup latency. |
| Elastic IP + local TLS proxy (ACM exportable cert) | AWS-managed renewal, but $7.00/FQDN per issuance/renewal and still host-installed. |
| Internet-facing ALB + ACM | Free integrated cert and stable DNS alias, but ~$16.4/month + LCU + a second public IPv4 while running. Deferred to the migration threshold (prototype open question #8). |
| Domain registered via third-party registrar | Often slightly cheaper; requires pointing name servers to Route 53 or using the registrar's DNS. |

## 4. Decisions, assumptions, and owner

- Owner: repository owner.
- Decision: the apex domain `joericearchitect.com` and the Route 53 hosted zone are created in Phase 1; this phase adds the public `A` record and uses Route 53 as the DNS service.
- Decision: default ingress is the on-demand Elastic IP + host TLS proxy; do not provision an ALB or use ACM integrated certificates in this phase.
- Decision: Terraform controls the `A` record and updates it on each cold start; the Elastic IP is released on shutdown.
- Assumptions: `joericearchitect.com` is confirmed available for registration (checked 2026-08-23); HTTPS is publicly available (no source-IP allowlist); the TLS method (Let's Encrypt vs ACM exportable) is finalized before implementation.
- Deferred: ALB + ACM, Jenkins/CI exposure, and any multi-user or multi-account exposure.

## 5. Scope, non-goals, constraints, dependencies, and risks

### Scope

- Route 53 public `A` record for `sonar.joericearchitect.com` (domain + hosted zone already created in Phase 1).
- TLS termination at the host (Let's Encrypt or ACM exportable).
- Elastic IP allocation/association on cold start and release on shutdown.
- Terraform automation of the DNS update.

### Non-goals

- ALB, ACM integrated certificates, WAF, or CDN in this phase.
- Exposing any port other than 443.
- High availability or multi-replica topology.

### Constraints and dependencies

- Phase 1 (the cold-off prototype) must be implemented first and registers the apex domain + Route 53 hosted zone; this brief adds the public `A` record, TLS, and 443 exposure.
- Terraform must control the DNS `A` record and update it when each cold start allocates a new public IP.
- Do not expose SonarQube 9000, PostgreSQL, Elasticsearch, SSH, Docker, or ECS-agent ports.
- Domain and certificate secrets must never enter Terraform state or the repository.

### Risks

- The public IP changes every session; DNS propagation and TLS readiness add startup time.
- A released-but-not-recreated Elastic IP, or a stale DNS record, can break access or leave an idle-IP charge.
- Losing the certificate/private key or the DNS-01 automation path can break HTTPS renewal.

## 6. Open questions and blocking decisions

1. ~~Hostname + domain availability~~ — **Resolved: `sonar.joericearchitect.com`; `joericearchitect.com` confirmed available (2026-08-23).**
2. TLS method: Let's Encrypt (ACME, free) or ACM exportable certificate ($7.00/FQDN)?
3. ~~HTTPS restriction~~ — **Resolved: publicly available (no IP allowlist).**
4. What threshold (cost, uptime, user count) triggers migration to ALB + ACM?

## 7. Recommended next step

Confirm the TLS method. Then specify the Terraform scaffold for the `A` record, Elastic IP lifecycle, and certificate automation, and define the cold-start DNS-update and shutdown EIP-release contracts. No OpenSpec artifacts were created by this brief.
