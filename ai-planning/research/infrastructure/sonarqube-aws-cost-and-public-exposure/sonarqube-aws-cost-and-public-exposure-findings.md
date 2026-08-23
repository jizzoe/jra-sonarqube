# sonarqube-aws-cost-and-public-exposure research findings

Depth: standard

## Summary
Summary: Current us-east-1 cost and public-exposure research for a singleton Dockerized SonarQube Community Build service on ECS EC2 capacity compared with the same Docker container on a direct EC2 host. Costs are on-demand estimates using 730 hours per month, exclude tax and internet data transfer, and are inputs to—not approval of—the architecture decision.

This supplements the primary [Community Build architecture research](../sonarqube-community-edition-aws-ai-sdd/sonarqube-community-edition-aws-ai-sdd-findings.md). Its companion [sources.md](sources.md) is the dated pricing provenance.

## Executive answer

Your preference—**Dockerized SonarQube deployed as an ECS service on EC2 capacity**—has no material ECS price premium over Docker directly on the same EC2 instance. AWS charges no ECS orchestration/control-plane fee and no EC2 launch-type management fee. The same EC2, EBS, RDS, public IPv4, logs, backup, and data-transfer charges apply either way.

Choose ECS because it gives the desired deployment model: task definitions, IAM separation, service health/deployment semantics, and repeatable image changes. Do not select ECS Managed Instances unless its managed-host value is intentional; it adds a management fee. Do not use Fargate: the Community Build host requirements rule it out for production.

## Baseline cost model — us-east-1, on demand

Assumptions: one singleton ECS service on a self-managed EC2 Auto Scaling group capacity provider; 730 hours/month; x86 Linux; no NAT gateway; 30 GiB gp3 application EBS; 30 GiB RDS gp3; current PostgreSQL; no taxes or Internet egress. The compute choice uses `t3.large` rather than the nominal 4-GiB minimum so that the operating system, ECS agent, and SonarQube do not compete for exactly the documented 4 GiB starting requirement.

| Component | Calculation | Monthly estimate |
| --- | --- | ---: |
| ECS service on EC2 capacity | ECS control plane and EC2 launch type | **$0.00** |
| EC2 host | `t3.large`: $0.0835 × 730 | **$60.96** |
| Application state volume | 30 GiB gp3 EBS × $0.08 | **$2.40** |
| RDS PostgreSQL compute | `db.t3.large`, Single-AZ: $0.145 × 730 | **$105.85** |
| RDS storage | 30 GiB gp3 × $0.115 | **$3.45** |
| **Private/base subtotal** |  | **$172.66/month** |

These are rate-card estimates, not a bill cap. T3 EC2 and RDS are burstable; sustained CPU above baseline can add Unlimited-mode CPU-credit charges. The first Terraform version should expose sizing variables and create a budget alarm.

### ECS EC2 versus direct Docker on EC2

| Cost category | ECS service on EC2 capacity | Docker directly on EC2 | Difference |
| --- | ---: | ---: | ---: |
| EC2 host / EBS / RDS | Same | Same | $0 |
| ECS control plane / EC2 launch type | $0 | N/A | $0 |
| Image registry, CloudWatch, backups, data transfer | Depends on chosen services and usage | Same categories | Usually $0 or usage-driven |
| Operational model | ECS task/service/IAM/deployments | Host-managed Compose/systemd/deployments | Engineering tradeoff, not an AWS fee |

The common ECS-specific surprise is selecting **ECS Managed Instances** rather than an EC2 Auto Scaling group capacity provider; Managed Instances has an additional fee. The scaffold should explicitly use the latter.

### RDS availability choice

| RDS deployment | Compute + 30 GiB gp3 storage | Meaning |
| --- | ---: | --- |
| Single-AZ `db.t3.large` | about **$109.30/month** | Lowest-cost managed database baseline; restoration is from backup on an AZ/instance failure. |
| Multi-AZ `db.t3.large` with one standby | about **$218.60/month** | Roughly doubles database compute and storage, providing managed standby/failover. |

RDS, not ECS, is the dominant baseline cost. Multi-AZ adds roughly **$109/month** before backup/data-transfer variation. Start Single-AZ unless the design brief establishes an availability objective that needs automated database failover; retain tested backups and a restore runbook either way.

## Public exposure options

### Recommended: public ALB, private ECS/EC2 host

Use an Internet-facing ALB with an ACM certificate and a DNS name such as `sonarqube.example.com`; keep the EC2 host/task private. In us-east-1, the ALB base is $0.0225/hour (about $16.43/month). An Internet-facing ALB normally consumes two in-use public IPv4 addresses (about $7.30/month), so the fixed public-edge baseline is about **$23.73/month plus LCU traffic charges**.

This is the best security/operability default: TLS terminates at a managed edge, the task accepts port 9000 only from the ALB security group, certificate renewal is managed, health checks are integrated, and replacement hosts do not become the public contract.

### Cheapest: public Elastic IP on the one ECS EC2 host

One in-use public IPv4/Elastic IP costs $0.005/hour, approximately **$3.65/month** at 730 hours. Relative to the ALB edge, this can save roughly **$20/month plus ALB LCU usage**. It is only reasonable for a deliberately singleton, low-traffic environment where the lower cost is worth making that instance and its reverse proxy the public boundary.

To expose the service this way, Terraform and deployment configuration need:

1. An EC2 instance in a public subnet, route to an Internet Gateway, and an Elastic IP associated with its network interface.
2. A singleton Auto Scaling group/service (`min = desired = max = 1`) and a recovery procedure that moves the Elastic IP to a replacement host.
3. A host-level or host-network reverse proxy on 443 forwarding only to the local/container port 9000. Do not expose port 9000 directly to the Internet.
4. Security groups allowing 443 only from the intended population; no public database, search, SSH, Docker, or ECS-agent ports. Use SSM instead of inbound SSH.
5. A DNS name pointing to the Elastic IP. ACM public certificates require a fully qualified domain name. A browser visiting a raw IP over HTTPS will reject a normal DNS certificate because the URL hostname does not match; raw `http://<ip>:9000` is not production-safe because SonarQube only accepts inbound plain HTTP.

Direct-IP exposure trades roughly $20/month for less resilient routing, host-level proxy/certificate operations, harder replacement, and a larger public blast radius. It is feasible, but not the preferred production default.

## Costs intentionally excluded

- Internet egress, CloudWatch Logs ingestion/retention, alarms, and Database Insights.
- Backup/snapshot growth beyond included automated-backup allocation, manual snapshots, and restore testing.
- DNS hosted zone, WAF, ECR, KMS, and any NAT gateway. A NAT gateway can materially exceed the ECS fee that does not exist, so a private-subnet topology needs its own egress decision.
- Taxes, Savings Plans/Reserved Instances, and CPU Unlimited-credit overages.

## Verified facts
- ECS has no separate orchestration or EC2 launch-type management fee. ECS on EC2 bills the EC2 instances and created resources. ECS Managed Instances, by contrast, adds a per-instance management fee and is not the intended launch model.
- AWS recommends capacity providers for compute configuration. A self-managed EC2 Auto Scaling group capacity provider is supported for ECS services and is the appropriate ECS pattern when host-level SonarQube prerequisites are required.
- In us-east-1, Linux t3.medium is 2 vCPU/4 GiB at $0.0418/hour and t3.large is 2 vCPU/8 GiB at $0.0835/hour. T3 instances are burstable and can incur Unlimited-mode CPU credit charges if sustained usage exceeds baseline.
- RDS PostgreSQL pricing includes DB instance time, provisioned storage, backup storage, and data transfer. Multi-AZ with one standby automatically fails over; T3/T4g databases use Unlimited mode, with $0.075 per vCPU-hour CPU credits over baseline.
- Live public price-list extraction on 2026-08-21 returned PostgreSQL db.t3.large at $0.145/hour Single-AZ and $0.290/hour Multi-AZ. General Purpose-GP3 RDS storage entries were $0.115/GB-month Single-AZ and $0.230/GB-month Multi-AZ.
- EBS bills provisioned GB-month. gp3 includes 3,000 IOPS and 125 MB/s baseline without added IOPS or throughput cost; the documented pricing example uses $0.08/GB-month in a region with that rate.
- An Application Load Balancer is billed for running time and Load Balancer Capacity Units. The us-east-1 example uses $0.0225 per ALB-hour plus $0.008 per LCU-hour; traffic determines LCU consumption.
- In-use and idle public IPv4 addresses cost $0.005 per address-hour, including resources in VPCs. A 730-hour month makes one address approximately $3.65; the documented example counts two in-use public IPv4 addresses for one Elastic Load Balancer.
- For direct internet access, attach an internet gateway, route the subnet to it, assign a public or Elastic IP address, and restrict security groups. Internet gateways have no charge, but associated EC2 data transfer is billable.
- ACM public certificate requests require a fully qualified domain name and validate domain control. ACM integrated certificates fit HTTPS load balancers; for certificate automation outside integrated services such as EC2, AWS points to ACME.

## Source-reported claims
- CloudWatch log ingestion is usage-based. AWS pricing examples use $0.50 per GB ingested in us-east-1, so log retention, metric alarms, and dashboards should be explicitly budgeted rather than assumed free.

## Assistant inferences
- ECS on EC2 capacity and Docker directly on that EC2 instance have a zero-dollar ECS service-fee difference. ECS is justified by repeatability and operational structure, not expected compute savings.
- For this small singleton deployment, RDS availability posture and the choice of ALB versus a direct Elastic IP are the meaningful fixed-cost levers.

## Unknowns
- AWS region; all dollar figures above assume us-east-1 and must be recalculated for the selected region.
- Expected users, scanner frequency, codebase size, storage growth, and Internet egress.
- Availability objective and whether RDS Multi-AZ is required.
- Whether the public endpoint must serve anonymous users, corporate users, GitHub-hosted CI, or only VPN/self-hosted runners.

## Recommendations
- Implement the preferred ECS-on-EC2 model using a self-managed EC2 Auto Scaling group capacity provider, not Fargate or ECS Managed Instances.
- Set a $200/month initial infrastructure budget alarm for the Single-AZ private baseline, then revise it after sizing and public-ingress decisions.
- Prefer ALB + ACM + DNS for production exposure. Retain direct EIP exposure as an explicitly lower-cost, singleton-risk option rather than the default.

## Model guidance provenance
- Role: balanced-standard
- Lookup date: 2026-08-21
- codex: gpt-5.6-terra; source: https://developers.openai.com/codex/models; stale-risk; verify current official provider documentation before use

## Use cases
- Select the ECS EC2 deployment shape, RDS availability tier, and public endpoint before Terraform module interfaces are chosen.

## SDLC fit
- Capture the cost assumptions in the design brief and turn them into Terraform variables, budget alarms, and acceptance evidence rather than unexplained defaults.

## Open-source and paid options
- ECS on EC2 capacity has no ECS fee; ECS Managed Instances has an added fee. Community Build removes Sonar licensing cost but not AWS compute, database, storage, observability, and network cost.

## Tutorials and articles
- The AWS Pricing Calculator is the final source of truth for the selected region and usage profile. Re-run it immediately before implementation because rates and assumed traffic change.

## Project fit
- ECS EC2 fits the requested Dockerized deployment while meeting SonarQube’s host-level Linux requirements. Keep the initial service singleton and make recovery/upgrade procedures first-class infrastructure deliverables.

## Source material used as data
### Amazon ECS pricing
> ECS has no separate orchestration or EC2 launch-type management fee. ECS on EC2 bills the EC2 instances and created resources. ECS Managed Instances, by contrast, adds a per-instance management fee and is not the intended launch model.

### Amazon ECS launch types and capacity providers
> AWS recommends capacity providers for compute configuration. A self-managed EC2 Auto Scaling group capacity provider is supported for ECS services and is the appropriate ECS pattern when host-level SonarQube prerequisites are required.

### Amazon EC2 T3 instances
> In us-east-1, Linux t3.medium is 2 vCPU/4 GiB at $0.0418/hour and t3.large is 2 vCPU/8 GiB at $0.0835/hour. T3 instances are burstable and can incur Unlimited-mode CPU credit charges if sustained usage exceeds baseline.

### Amazon RDS for PostgreSQL pricing
> RDS PostgreSQL pricing includes DB instance time, provisioned storage, backup storage, and data transfer. Multi-AZ with one standby automatically fails over; T3/T4g databases use Unlimited mode, with $0.075 per vCPU-hour CPU credits over baseline.

### Amazon RDS us-east-1 public price list
> Live public price-list extraction on 2026-08-21 returned PostgreSQL db.t3.large at $0.145/hour Single-AZ and $0.290/hour Multi-AZ. General Purpose-GP3 RDS storage entries were $0.115/GB-month Single-AZ and $0.230/GB-month Multi-AZ.

### Amazon EBS pricing
> EBS bills provisioned GB-month. gp3 includes 3,000 IOPS and 125 MB/s baseline without added IOPS or throughput cost; the documented pricing example uses $0.08/GB-month in a region with that rate.

### Elastic Load Balancing pricing
> An Application Load Balancer is billed for running time and Load Balancer Capacity Units. The us-east-1 example uses $0.0225 per ALB-hour plus $0.008 per LCU-hour; traffic determines LCU consumption.

### Amazon VPC pricing
> In-use and idle public IPv4 addresses cost $0.005 per address-hour, including resources in VPCs. A 730-hour month makes one address approximately $3.65; the documented example counts two in-use public IPv4 addresses for one Elastic Load Balancer.

### Enable internet access for a VPC using an internet gateway
> For direct internet access, attach an internet gateway, route the subnet to it, assign a public or Elastic IP address, and restrict security groups. Internet gateways have no charge, but associated EC2 data transfer is billable.

### AWS Certificate Manager public certificates
> ACM public certificate requests require a fully qualified domain name and validate domain control. ACM integrated certificates fit HTTPS load balancers; for certificate automation outside integrated services such as EC2, AWS points to ACME.

### Amazon CloudWatch pricing
> CloudWatch log ingestion is usage-based. AWS pricing examples use $0.50 per GB ingested in us-east-1, so log retention, metric alarms, and dashboards should be explicitly budgeted rather than assumed free.

### Cost-comparison synthesis
> For the same x86 EC2 host, ECS on EC2 and direct Docker-on-EC2 have a zero-dollar ECS cost difference. Choose ECS for desired deployment and IAM/service structure, not expected compute savings. The material cost decisions are RDS class/HA and ALB versus a direct public endpoint.
