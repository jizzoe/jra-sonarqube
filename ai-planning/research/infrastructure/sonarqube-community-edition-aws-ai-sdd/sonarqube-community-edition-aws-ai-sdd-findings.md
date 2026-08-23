# sonarqube-community-edition-aws-ai-sdd research findings

Depth: deep

## Summary
Summary: Deep, current research for deploying and operating the maintained SonarQube Community Build on AWS and integrating its evidence into a global AI-skills and spec-driven-development workflow. The recommended direction is a single SonarQube node on ECS EC2 capacity, not Fargate, with PostgreSQL on RDS and a deliberately least-privileged, read-only agent integration.

This is a research record, not an approved architecture. The companion [sources.md](sources.md) contains the dated provenance for every claim.

Current cost and direct-public-IP details are in the companion [AWS cost and public-exposure research](../sonarqube-aws-cost-and-public-exposure/sonarqube-aws-cost-and-public-exposure-findings.md).

## Decision-ready synthesis

The project should target **SonarQube Community Build**, the currently maintained free/open-source community line. In user-facing repository text, call it “SonarQube Community Build (Community Edition)” once and then use “Community Build” so that the project is not tied to an outdated product name.

The initial ECS Fargate concept should be rejected. SonarSource explicitly lists AWS Fargate among environments that cannot satisfy its embedded Elasticsearch Linux prerequisites and says those environments are unsupported for enterprise production. The viable managed-container baseline is a singleton ECS service on EC2 Auto Scaling group capacity, with the host bootstrapped for SonarQube’s kernel and ulimit requirements. A direct EC2 Docker deployment remains a simpler alternative and must be compared in the design brief.

The usable baseline is:

```text
GitHub-hosted CI / browsers / approved agent clients
                    |
             HTTPS + public DNS
                    |
        ALB + ACM certificate + optional WAF
                    |
       private subnet: ECS service, desired count = 1
       EC2 host bootstrap: sysctls + ulimits required by Elasticsearch
                    |
  PostgreSQL on RDS              explicit persistent volume for SonarQube state
                    |
   CloudWatch logs, metrics, alarms, RDS backups, recovery runbook
```

The singleton assumption is intentional, not an availability claim: Community Build embeds Elasticsearch and depends on node-local operational prerequisites. A second active application replica or automated horizontal scaling must not be scaffolded as “high availability” without a product-supported topology and a tested state/storage design.

## Comparative analysis

| Option | Status | Why |
| --- | --- | --- |
| ECS on Fargate + RDS | Reject | SonarSource explicitly marks Fargate unsupported because Elasticsearch prerequisites cannot be met. |
| ECS on EC2 capacity provider + RDS | Recommended baseline | Preserves ECS service management while allowing host bootstrapping, ALB integration, task IAM, and explicit durable storage. |
| Docker Compose on a dedicated EC2 instance + RDS | Viable simpler baseline | Fewer ECS moving parts and direct host control; less managed scheduling and deployment integration. |
| EKS + RDS | Defer | Kubernetes is supported, but adds operational surface without an identified need. It does not remove the Linux prerequisite or singleton-state problem. |

The RDS database is the system of record. SonarQube can rebuild Elasticsearch indexes after a database restore; the recovery sequence is stop service, restore the database, remove `data/es8`, then start the service. Persistent application directories still need an explicit volume and documented lifecycle, especially extensions and logs. Treat task replacement as a recovery/deployment event, not horizontal scaling.

## Installation and configuration pattern

- Bootstrap the ECS EC2 AMI or launch template before any task starts: `vm.max_map_count >= 524288`, `fs.file-max >= 131072`, a 131072 file-descriptor limit, and an 8192 thread limit for the SonarQube runtime.
- Pin a tested Community Build image version and make upgrades an explicit input; never use a floating `latest` tag for the production service.
- Use RDS PostgreSQL rather than embedded H2. Current Sonar documentation supports PostgreSQL 14–18 from Community Build 26.2 onward; choose an engine/version combination deliberately and pin it in Terraform variables.
- Inject `SONAR_JDBC_URL`, `SONAR_JDBC_USERNAME`, `SONAR_JDBC_PASSWORD`, the session JWT secret, and any monitoring passcode from Secrets Manager. Do not put values in Terraform state, `.tfvars`, a task-definition literal, or an agent configuration file.
- Place the task and RDS in private subnets. Expose only ALB HTTPS publicly; permit task port 9000 only from the ALB security group, RDS only from the task security group, and keep the embedded search port private.
- Terminate TLS at the ALB with ACM and supply the proxy headers SonarQube requires. Use a stable externally reachable base URL if GitHub-hosted CI must reach the server.

## Maintenance and recovery

| Control | Required evidence |
| --- | --- |
| Database recovery | Explicit nonzero RDS backup retention, manual pre-upgrade snapshot, and a tested point-in-time restore runbook. |
| SonarQube restore | Document the stop → database restore → delete `data/es8` → restart/reindex sequence. |
| Image upgrade | Read every intervening release note, test against a restored copy, and confirm database free space is below 50% before migration because it may temporarily double. |
| Observability | Ship SonarQube main, web, compute-engine, search, access, and API-deprecation logs; alarm on task health, RDS capacity/availability, CPU/memory, disk, and health API failure. |
| Health probes | Use an ALB readiness path appropriate for anonymous traffic and independently check authenticated `/api/system/health`; ALB health checks alone do not prove database or compute-engine health. |
| Token hygiene | Use project-analysis tokens in CI where possible, set expirations, rotate before expiry, and keep user tokens away from CI. |

## CI and integration limits

Community Build’s analysis model is main-branch analysis. It does **not** provide the multiple-branch or pull-request analysis/decoration features of higher editions. This is a product constraint, not an IaC gap.

For GitHub Actions, the scaffold should provide a reusable example—not an enabled organization policy—that performs a full checkout, builds/tests and produces coverage before `SonarSource/sonarqube-scan-action@v7`, and passes a project-specific `SONAR_TOKEN` plus `SONAR_HOST_URL`. Pin the action to an immutable commit SHA when it is actually adopted. Use `sonar.qualitygate.wait=true` only where a deployment must be blocked; it adds polling time and cannot turn Community Build into PR decoration.

Use HMAC-protected webhooks when a receiving system needs asynchronous analysis evidence. Store the webhook secret separately and verify the `X-Sonar-Webhook-HMAC-SHA256` signature. A webhook consumer may record quality-gate evidence, but must not merge, deploy, or change issues merely because an agent requested it.

## AI-agent and SDD integration

### Recommended operating model

1. An agent reads a bounded SDD task/specification and changes code only under the usual repository approval policy.
2. CI runs tests, coverage generation, and the Sonar scanner against the protected main branch.
3. SonarQube calculates the quality gate; CI/webhook records a link, task ID, timestamp, and gate result as evidence.
4. An agent may query issues, measures, rules, and quality-gate status to explain failures and propose a patch or test plan.
5. A human review plus normal CI determines whether the proposal is accepted. SonarQube findings are evidence, not authorization for an agent to merge, deploy, alter quality gates, or resolve issues.

This separates evidence retrieval from mutation and keeps the SDD lifecycle auditable. The Web API is a stable fallback where MCP is unavailable; use bearer auth, runtime API documentation, API-version/deprecation checks, and a narrowly permissioned account.

### Free MCP options found

| Server | Cost/license posture | Fit and guardrails |
| --- | --- | --- |
| [Official SonarQube MCP Server](https://github.com/SonarSource/sonarqube-mcp-server) | Available without a separate server license, but **source-available SSAL v1.0**, not OSI open source. It has active releases and optional anonymous telemetry (disable with `TELEMETRY_DISABLED=true`). | Best feature breadth and current maintenance. For this workflow, configure local stdio transport, `SONARQUBE_READ_ONLY=true`, one project key where possible, and only `issues,quality-gates,measures,rules,projects` toolsets. It requires a USER token for Server connections, so create a dedicated non-admin user with only Browse permissions. |
| [wadew/sonar-mcp](https://github.com/wadew/sonar-mcp) | MIT-licensed, open-source Python implementation. | It advertises Community Edition projects, metrics, quality gates, issues, and reports. It is a credible no-fee/open-source candidate but is not official; establish maintenance, dependency, token-scoping, transport, and test evidence before adding it to a global skill. |

Do not expose either MCP server as an unauthenticated shared HTTP endpoint in the first release. Prefer per-developer stdio for local agent use. If shared transport later becomes necessary, use TLS, distinct user tokens, read-only server/tool configuration, reverse-proxy access control, network isolation, and an explicit security review. Never pass a SonarQube token through prompt text or commit it in agent settings.

### AI-related SonarQube features

The current Community Build feature comparison lists AI Code Assurance, while paid tiers/add-ons retain advanced SAST, dependency-risk SCA, portfolios, and some management features. Do not design around AI CodeFix, the remediation agent, PR analysis, or dependency-risk tools as free Community Build functionality. Validate the exact Community Build image’s feature set during acceptance before enabling an “AI-assured” quality gate or badge.

## Verified facts
- Community Build supports installation from ZIP, Docker image, or Kubernetes/OpenShift; production setup includes host, database, networking, and plugin guidance.
- Production Community Build needs a separate low-latency database. A small installation starts at 2 cores, 4 GB RAM, and 30 GB disk. Environments unable to meet Elasticsearch Linux prerequisites, including AWS Fargate, are unsupported and unreliable for enterprise production.
- The host must set vm.max\_map\_count to at least 524288, fs.file-max to at least 131072, and allow the SonarQube user at least 131072 file descriptors and 8192 threads; these limits apply regardless of Docker or Kubernetes installation.
- Containerized production use requires external database settings SONAR\_JDBC\_URL, SONAR\_JDBC\_USERNAME, and SONAR\_JDBC\_PASSWORD and persists data, extensions, and logs. Docker image tags should be selected deliberately rather than implicitly using latest.
- H2 is only for tests, not production. Community Build 26.2 supports PostgreSQL 14 through 18 and recommends a separate low-latency database. Its AWS RDS example starts at db.t3.large with 30 GB table space, subject to monitoring and adjustment.
- SonarQube accepts only plain HTTP inbound, so a reverse proxy is required for TLS. The proxy must set X-Forwarded-Proto and X-Forwarded-For for HTTPS and should forward Sonar-MD5 so scanners can verify downloaded plugin integrity.
- Browsers, scanners, IDE connected mode, and DevOps systems use the Web API. Cloud-hosted CI requires a reachable public base URL; SonarQube connects to the database with JDBC and sends webhooks over HTTP\(S\).
- A unique base64 HS256 JWT secret can preserve sessions across restarts. Monitoring can use SONAR\_WEB\_SYSTEMPASSCODE, while the Elasticsearch port is a security-sensitive loopback service and must not be exposed publicly.
- The api/system/health Web API provides instance health. Monitor the Compute Engine, Elasticsearch, and Web Java processes along with CPU, memory, and disk, especially above 100 users, 5 million lines of code, or CI-intensive operation.
- Use database backup tooling; hot database backups are supported. To restore, stop SonarQube, restore the database, delete the Elasticsearch index directory data/es8, and restart so indexes are rebuilt.
- Read every intervening release note, take a database backup, and ensure database disk use is below 50 percent before an upgrade because migrations may temporarily require up to twice the normal table space.
- SonarQube produces rotated main, web, compute-engine, search, access, and API-deprecation logs. The web log is particularly useful for database connectivity, migrations, reindexing, and HTTP-request troubleshooting.
- Community Build exposes Web APIs documented in the running instance. Bearer authentication with a user token is recommended; API V2 will gradually replace endpoints, and POST parameters should use form data rather than query strings.
- Project analysis tokens are encouraged because compromise is scoped to one project. User tokens have the issuer permissions and are required for some user-level integrations; responses expose a token-expiration header to aid rotation.
- Community Build analyzes a project main branch through a scanner running in CI. Multiple-branch and pull-request analysis are supported by other SonarQube deployments, not Community Build.
- GitHub integration provides code quality and security workflow support, but Community Build does not support multiple-branch or pull-request analysis features.
- The documented GitHub Actions pattern uses SonarSource/sonarqube-scan-action v7 with a full checkout and a project-specific SONAR\_TOKEN plus SONAR\_HOST\_URL. A quality-gate wait can fail a deployment job, but pull-request decoration is unavailable in Community Build.
- Webhooks notify on completed analyses and quality-gate-affecting issue changes. Payloads include task and quality-gate status, and HMAC-SHA256 secrets can authenticate deliveries.
- The current feature table lists AI Code Assurance in Community Build but reserves capabilities such as applications, portfolios, advanced SAST, and dependency-risk SCA for higher editions or add-ons. Design assumptions must be validated against the target release.
- The official MCP server connects agents to SonarQube Server using a USER token and URL. It supports selective toolsets and a cumulative read-only mode. It is source-available under SSAL v1.0, not an OSI open-source license, and telemetry can be disabled with TELEMETRY\_DISABLED=t…
- The official MCP server has current releases and advises using the sonarsource/sonarqube-mcp image rather than the former mcp/sonarqube image. Its release notes restored branch parameters for relevant tools.

## Source-reported claims
- This MIT-licensed Python MCP server describes itself as a Community Edition integration and exposes projects, metrics, quality-gate status, issues, reports, and prompt templates. It should undergo normal dependency, maintenance, and least-privilege review before use.
- OpenAI documents gpt-5.6-sol as the frontier model for complex capability, gpt-5.6-terra for intelligence-cost balance, and gpt-5.6-luna for efficient high-volume work. The research workflow maps deep research to its highest-quality role; this is advisory only and does not chang…

## Assistant inferences
- AWS recommends capacity providers for service compute configuration. Because Fargate is unsupported by SonarQube, an ECS cluster using an EC2 Auto Scaling group capacity provider is the managed-container option that permits host-level Elasticsearch prerequisites.
- ECS can configure one EBS volume at service deployment from a task definition volume marked configuredAtLaunch. For a singleton service, persistent state requires an explicit volume and failover/recovery procedure rather than assuming task-local storage survives replacement.

## Unknowns
- Expected number of users, projects, and lines of code; these determine compute/RDS class and disk sizing.
- Availability target and recovery-time/recovery-point objectives; these determine RDS Multi-AZ, backup retention, and the amount of EC2/EBS recovery automation justified.
- Whether the SonarQube base URL can be restricted to corporate/VPN access while remaining reachable by the chosen CI runners.
- Authentication choice (local accounts, GitHub OAuth, or identity-provider integration) and the organizational boundary for projects/tokens.
- Whether the intended “global AI skills” platform permits local stdio MCP configuration only or needs a centrally hosted, security-reviewed MCP service.

## Recommendations
- Store database credentials and session secrets in Secrets Manager and reference them from the ECS task definition. Grant the task execution role only the required secret retrieval permissions; never place secret values in Terraform state, container environment files, or reposito…
- Configure an explicit nonzero RDS backup retention period and test point-in-time restore. AWS allows 0 to 35 days for DB instances, and setting 0 disables automated backups; do not accept the create-path default as policy.
- Enable CloudWatch alarms for RDS capacity and availability signals and create an operational dashboard. RDS publishes core metrics at one-minute periods by default, allowing thresholds to align with SonarQube database and analysis demand.
- Publish PostgreSQL logs to CloudWatch Logs. RDS retains logs locally for one to seven days depending on rds.log\_retention\_period, so CloudWatch gives longer-lived troubleshooting evidence.
- Use an ALB HTTPS listener with ACM certificate management. Restrict the SonarQube task security group to inbound port 9000 only from the ALB security group, and consider WAF or identity-aware access at the ALB as appropriate.
- Configure ALB health checks deliberately and pair them with authenticated api/system/health monitoring. An ALB considers targets healthy based on configured HTTP\(S\) checks, but if all targets are unhealthy it can fail open, so a singleton service needs independent alerts.
- Pin third-party GitHub Actions to immutable full-length commit SHAs, set the minimum workflow permissions, and prefer short-lived OpenID Connect credentials over long-lived cloud access keys for AWS deployment workflows.
- Treat SonarQube as an evidence provider, not an autonomous change authority: CI analyzes the protected main branch, records immutable quality-gate evidence, and exposes an MCP or Web API client configured read-only with narrow toolsets. Agents propose fixes and tests; normal rev…

## Model guidance provenance
- Role: highest-quality
- Lookup date: 2026-08-21
- codex: `gpt-5.6-sol`; source shown by the workflow: https://developers.openai.com/codex/models; stale-risk; verify current official provider documentation before use.
- Current verification: [official OpenAI model guidance](https://developers.openai.com/api/docs/guides/latest-model) on 2026-08-21 identifies `gpt-5.6-sol` as the flagship/frontier option. This was advisory research-role provenance only; the active session model was not changed.

## Further decision framing
- See Decision-ready synthesis and the evidence classification above.

## Tradeoffs
- ECS on EC2 gains managed scheduling but requires AMI/launch-template lifecycle and host tuning. A single EC2 Docker service reduces orchestration complexity but shifts deployment/health management into the instance design.
- Community Build avoids Sonar licensing cost but removes PR/multi-branch analysis and paid security features. Do not overcomplicate the initial infrastructure to imitate features the edition does not provide.
- A locally spawned MCP process minimizes shared-service exposure but depends on each developer’s secure local setup. A shared MCP service centralizes controls but requires its own auth, TLS, isolation, audit, and incident model.

## Maturity signals
- SonarSource’s official MCP server has current releases and explicit selective-tool/read-only controls, supporting a controlled pilot.
- The non-official MIT alternative is viable to evaluate, but its maintenance/security posture needs repository-specific due diligence before it becomes part of an organization-wide agent stack.

## Implementation patterns
- Make Terraform modules align with responsibility boundaries: network/edge, ECS-EC2 capacity and host bootstrap, SonarQube service/storage, PostgreSQL RDS, secrets/IAM, and observability. This is a proposed scaffold decomposition, not yet an approved module interface.
- Keep infrastructure state and application configuration distinct. Terraform creates secret containers and grants access; a secure deployment/bootstrap process supplies secret values.
- Use one task and one durable state attachment initially. Scale scanner execution in CI rather than application replicas.

## Risks
- Deploying on Fargate is a supportability risk, not an optimization opportunity.
- A single instance creates an availability risk; mitigate through clear restoration rather than claiming unsupported high availability.
- An MCP server that receives a powerful user token can become an administrative path even when an agent prompt says “read only”; enforce both token permissions and MCP tool restrictions.
- Floating container/action versions, token leakage, publicly reachable search/DB ports, and untested restores are high-probability operational failures for the scaffold to prevent.

## Source quality notes
- 30 of the 33 sources are first-party SonarSource, AWS, GitHub, or OpenAI documentation; they support technical, product, API, and policy claims.
- The official MCP repository is authoritative for its own configuration, release, telemetry, and license statements. The MIT community MCP repository is authoritative only for its stated implementation and license; it is not a security endorsement.
- Source pages were accessed on 2026-08-21. Version-sensitive claims—especially Community Build features, image tags, scanner actions, MCP releases, and model guidance—must be rechecked immediately before implementation.

## Source material used as data
### Server installation and setup
> Community Build supports installation from ZIP, Docker image, or Kubernetes/OpenShift; production setup includes host, database, networking, and plugin guidance.

### Server host requirements
> Production Community Build needs a separate low-latency database. A small installation starts at 2 cores, 4 GB RAM, and 30 GB disk. Environments unable to meet Elasticsearch Linux prerequisites, including AWS Fargate, are unsupported and unreliable for enterprise production.

### On Linux systems
> The host must set vm.max\_map\_count to at least 524288, fs.file-max to at least 131072, and allow the SonarQube user at least 131072 file descriptors and 8192 threads; these limits apply regardless of Docker or Kubernetes installation.

### Set up and start your container
> Containerized production use requires external database settings SONAR\_JDBC\_URL, SONAR\_JDBC\_USERNAME, and SONAR\_JDBC\_PASSWORD and persists data, extensions, and logs. Docker image tags should be selected deliberately rather than implicitly using latest.

### Installing database
> H2 is only for tests, not production. Community Build 26.2 supports PostgreSQL 14 through 18 and recommends a separate low-latency database. Its AWS RDS example starts at db.t3.large with 30 GB table space, subject to monitoring and adjustment.

### Securing behind a proxy
> SonarQube accepts only plain HTTP inbound, so a reverse proxy is required for TLS. The proxy must set X-Forwarded-Proto and X-Forwarded-For for HTTPS and should forward Sonar-MD5 so scanners can verify downloaded plugin integrity.

### Networking requirements
> Browsers, scanners, IDE connected mode, and DevOps systems use the Web API. Cloud-hosted CI requires a reachable public base URL; SonarQube connects to the database with JDBC and sends webhooks over HTTP\(S\).

### List of system properties
> A unique base64 HS256 JWT secret can preserve sessions across restarts. Monitoring can use SONAR\_WEB\_SYSTEMPASSCODE, while the Elasticsearch port is a security-sensitive loopback service and must not be exposed publicly.

### SonarQube instance monitoring
> The api/system/health Web API provides instance health. Monitor the Compute Engine, Elasticsearch, and Web Java processes along with CPU, memory, and disk, especially above 100 users, 5 million lines of code, or CI-intensive operation.

### Backup and restore
> Use database backup tooling; hot database backups are supported. To restore, stop SonarQube, restore the database, delete the Elasticsearch index directory data/es8, and restart so indexes are rebuilt.

### Pre-update steps
> Read every intervening release note, take a database backup, and ensure database disk use is below 50 percent before an upgrade because migrations may temporarily require up to twice the normal table space.

### Server logs
> SonarQube produces rotated main, web, compute-engine, search, access, and API-deprecation logs. The web log is particularly useful for database connectivity, migrations, reindexing, and HTTP-request troubleshooting.

### Web API
> Community Build exposes Web APIs documented in the running instance. Bearer authentication with a user token is recommended; API V2 will gradually replace endpoints, and POST parameters should use form data rather than query strings.

### Managing your tokens
> Project analysis tokens are encouraged because compromise is scoped to one project. User tokens have the issuer permissions and are required for some user-level integrations; responses expose a token-expiration header to aid rotation.

### Analysis overview
> Community Build analyzes a project main branch through a scanner running in CI. Multiple-branch and pull-request analysis are supported by other SonarQube deployments, not Community Build.

### Introduction to GitHub integration
> GitHub integration provides code quality and security workflow support, but Community Build does not support multiple-branch or pull-request analysis features.

### Adding analysis to GitHub Actions workflow
> The documented GitHub Actions pattern uses SonarSource/sonarqube-scan-action v7 with a full checkout and a project-specific SONAR\_TOKEN plus SONAR\_HOST\_URL. A quality-gate wait can fail a deployment job, but pull-request decoration is unavailable in Community Build.

### Configuring webhooks
> Webhooks notify on completed analyses and quality-gate-affecting issue changes. Payloads include task and quality-gate status, and HMAC-SHA256 secrets can authenticate deliveries.

### Feature comparison table
> The current feature table lists AI Code Assurance in Community Build but reserves capabilities such as applications, portfolios, advanced SAST, and dependency-risk SCA for higher editions or add-ons. Design assumptions must be validated against the target release.

### SonarQube MCP Server
> The official MCP server connects agents to SonarQube Server using a USER token and URL. It supports selective toolsets and a cumulative read-only mode. It is source-available under SSAL v1.0, not an OSI open-source license, and telemetry can be disabled with TELEMETRY\_DISABLED=t…

### SonarQube MCP Server releases
> The official MCP server has current releases and advises using the sonarsource/sonarqube-mcp image rather than the former mcp/sonarqube image. Its release notes restored branch parameters for relevant tools.

### sonar-mcp
> This MIT-licensed Python MCP server describes itself as a Community Edition integration and exposes projects, metrics, quality-gate status, issues, reports, and prompt templates. It should undergo normal dependency, maintenance, and least-privilege review before use.

### Amazon ECS launch types and capacity providers
> AWS recommends capacity providers for service compute configuration. Because Fargate is unsupported by SonarQube, an ECS cluster using an EC2 Auto Scaling group capacity provider is the managed-container option that permits host-level Elasticsearch prerequisites.

### Specify Amazon EBS volume configuration at Amazon ECS deployment
> ECS can configure one EBS volume at service deployment from a task definition volume marked configuredAtLaunch. For a singleton service, persistent state requires an explicit volume and failover/recovery procedure rather than assuming task-local storage survives replacement.

### Specifying sensitive data using Secrets Manager secrets in Amazon ECS
> Store database credentials and session secrets in Secrets Manager and reference them from the ECS task definition. Grant the task execution role only the required secret retrieval permissions; never place secret values in Terraform state, container environment files, or reposito…

### Backup retention period
> Configure an explicit nonzero RDS backup retention period and test point-in-time restore. AWS allows 0 to 35 days for DB instances, and setting 0 disables automated backups; do not accept the create-path default as policy.

### Monitoring Amazon RDS metrics with Amazon CloudWatch
> Enable CloudWatch alarms for RDS capacity and availability signals and create an operational dashboard. RDS publishes core metrics at one-minute periods by default, allowing thresholds to align with SonarQube database and analysis demand.

### Parameters for logging in RDS for PostgreSQL
> Publish PostgreSQL logs to CloudWatch Logs. RDS retains logs locally for one to seven days depending on rds.log\_retention\_period, so CloudWatch gives longer-lived troubleshooting evidence.

### Infrastructure security in Elastic Load Balancing
> Use an ALB HTTPS listener with ACM certificate management. Restrict the SonarQube task security group to inbound port 9000 only from the ALB security group, and consider WAF or identity-aware access at the ALB as appropriate.

### Health checks for Application Load Balancer target groups
> Configure ALB health checks deliberately and pair them with authenticated api/system/health monitoring. An ALB considers targets healthy based on configured HTTP\(S\) checks, but if all targets are unhealthy it can fail open, so a singleton service needs independent alerts.

### Security hardening for GitHub Actions
> Pin third-party GitHub Actions to immutable full-length commit SHAs, set the minimum workflow permissions, and prefer short-lived OpenID Connect credentials over long-lived cloud access keys for AWS deployment workflows.

### Model guidance
> OpenAI documents gpt-5.6-sol as the frontier model for complex capability, gpt-5.6-terra for intelligence-cost balance, and gpt-5.6-luna for efficient high-volume work. The research workflow maps deep research to its highest-quality role; this is advisory only and does not chang…

### AI-agent and SDD integration assessment
> Treat SonarQube as an evidence provider, not an autonomous change authority: CI analyzes the protected main branch, records immutable quality-gate evidence, and exposes an MCP or Web API client configured read-only with narrow toolsets. Agents propose fixes and tests; normal rev…
