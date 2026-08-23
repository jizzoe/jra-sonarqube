# sonarqube-public-domain-and-dns research findings

Depth: standard

## Summary
Summary: Current requirements and cost for exposing the SonarQube Community Build UI at `sonar.joericearchitect.com`, including domain registration, Route 53 DNS, TLS, ingress options, the Terraform resources involved, and the residual cost that remains when the cold-off infrastructure is spun down.

This is a research record, not an approved architecture. The companion [sources.md](sources.md) contains the dated provenance for every claim.

This supplements the primary [Community Build architecture research](../sonarqube-community-edition-aws-ai-sdd/sonarqube-community-edition-aws-ai-sdd-findings.md) and the [AWS cost and public-exposure research](../sonarqube-aws-cost-and-public-exposure/sonarqube-aws-cost-and-public-exposure-findings.md).

## Decision-ready synthesis

Exposing the UI from a friendly hostname requires four pieces: a registered apex domain, a DNS hosted zone with an `A` record, a TLS certificate, and a public ingress path to the single ECS EC2 host.

The apex domain `joericearchitect.com` is registered once (annual fee) and a Route 53 public hosted zone hosts its records (small monthly fee). A single `A` record for `sonar.joericearchitect.com` points at either an on-demand Elastic IP or an alias to an Application Load Balancer.

The material fork is TLS/ingress:

| Path | TLS | Fixed cost while running | Notes |
| --- | --- | --- | --- |
| Elastic IP + local TLS proxy | Let's Encrypt (ACME) | ~$3.65/mo (EIP) | Free cert; DNS-01 challenge automation required; cert on host. |
| Elastic IP + local TLS proxy | ACM exportable cert | ~$3.65/mo (EIP) | $7.00/FQDN per issuance/renewal; AWS-managed renewal. |
| ALB + ACM | ACM public cert (free) | ~$16.4/mo + LCU + 2nd IPv4 (~$3.65) | Free integrated cert; stable DNS alias; deferred by prototype brief. |

When the infrastructure is cold (spun down), only two costs survive: the domain registration (~$14/year) and the hosted zone (~$0.50/month). Releasing the Elastic IP and destroying any ALB drive the rest to $0.

## What is required

### Domain registration
- Register the apex domain `joericearchitect.com` (confirm availability first).
- Route 53 registration (~$14/year for `.com`, annual, cannot be paid with AWS credits) automatically creates a hosted zone.
- Alternative: register at a third-party registrar and point name servers to Route 53, or use the registrar's DNS.

### DNS
- Public hosted zone for `joericearchitect.com` (~$0.50/month for the first 25 zones).
- One `A` record `sonar.joericearchitect.com` → Elastic IP, or an `A` alias → ALB.
- Standard queries ~$0.40/million; alias records to AWS resources (ELB, CloudFront, S3) are not charged.

### TLS certificate
- ACM public certificates are free but integrate only with ALB, CloudFront, API Gateway, and similar services; they cannot be installed directly on an EC2 instance.
- For a host-level proxy, use Let's Encrypt (ACME, free) or an ACM exportable public certificate ($7.00 per standard FQDN on issuance and each renewal).

### Ingress
- Elastic IP + host TLS proxy: security group permits 443 from a controlled source; the EIP is billed as a public IPv4 address.
- ALB + ACM: HTTPS listener with the ACM certificate; target group to the SonarQube task on 9000; adds fixed ALB cost and a second public IPv4.

## Terraform resources

- Domain (optional in Terraform): `aws_route53domains_registered_domain`, or register manually.
- DNS: `aws_route53_zone`, `aws_route53_record`.
- Elastic IP path: `aws_eip`, `aws_eip_association`, `aws_route53_record`; TLS via the `acme` provider or host user-data (Let's Encrypt) or an ACM exportable certificate.
- ALB path: `aws_acm_certificate`, `aws_acm_certificate_validation`, `aws_route53_record` (validation + alias), `aws_lb`, `aws_lb_target_group`, `aws_lb_listener`, `aws_lb_listener_rule`, `aws_security_group`.

## Cost model — us-east-1

### One-time / setup
| Item | Cost |
| --- | ---: |
| `.com` registration (Route 53) | ~$14 (recurs annually) |
| ACM exportable cert (EIP path, non-Let's-Encrypt) | $7.00/FQDN |

### Monthly while running
| Item | Monthly |
| --- | ---: |
| Route 53 hosted zone | $0.50 |
| DNS queries (single user) | ~$0 |
| Elastic IP (public IPv4) | ~$3.65 |
| ALB (only if used) | ~$16.4 + LCU + ~$3.65 (2nd IPv4) |

### Monthly when cold (infra spun down)
| Item | Cost |
| --- | ---: |
| Domain registration | ~$14/year (unavoidable) |
| Route 53 hosted zone | ~$0.50/month (unavoidable) |
| DNS queries | ~$0 |
| Elastic IP | $0 if released; ~$3.65 if left idle |
| ALB | $0 if destroyed |
| ACM cert (ALB path) | $0 (persists, auto-renews) |

The cold floor is therefore roughly $0.50/month plus ~$14/year for the name and its zone.

## Source material used as data
### Amazon Route 53 pricing
> Public hosted zones cost $0.50 per month; standard queries cost $0.40 per million. Alias records that route to AWS resources such as Elastic Load Balancing load balancers, CloudFront distributions, and S3 website buckets are provided at no additional charge.

### Registering a new domain (Route 53 Developer Guide)
> When you register a domain with Route 53, Route 53 automatically creates a hosted zone for the domain and charges a small monthly fee for the hosted zone in addition to the annual charge for the domain registration.

### Amazon VPC pricing
> In-use and idle public IPv4 addresses cost $0.005 per address-hour. A 730-hour month makes one address approximately $3.65.

### AWS Certificate Manager public certificates
> ACM public certificate requests require a fully qualified domain name and validate domain control. ACM integrated certificates fit HTTPS load balancers; for certificate automation outside integrated services such as EC2, AWS points to ACME.

### AWS Certificate Manager pricing — exportable certificates
> An exportable public certificate costs $7.00 per standard fully qualified domain name upon issuance and again only on certificate renewal.

### Elastic Load Balancing pricing
> An Application Load Balancer is billed for running time and Load Balancer Capacity Units. The us-east-1 example uses $0.0225 per ALB-hour plus $0.008 per LCU-hour.

## Recommendations
- Keep the Elastic IP + host TLS proxy path for phase 2 to match the prototype's cold-off cost target; reserve ALB + ACM for the migration threshold already captured in the prototype brief's open questions.
- Automate the DNS `A`-record update on every cold start, and release the Elastic IP on shutdown so no idle public-IPv4 charge accrues.
- Re-confirm rates in the AWS Pricing Calculator immediately before implementation.
