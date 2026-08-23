# Slice 00 — Account foundations

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Establish the persistent, low-cost account layer shared by both phases: the Terraform state backend, a $33/month budget alarm, and the Route 53 domain + hosted zone.

## Prerequisites

- `joe-rice-admin` and `jra-platform-bootstrap` exist (see the IAM bootstrap brief).

## Steps

1. Create the Terraform state S3 bucket (versioned, SSE-encrypted) and the DynamoDB lock table; add a `backend "s3"` block and confirm `terraform init` works against it.
2. Create the AWS Budgets alarm: $33 monthly cap, notification to `joericearchitect@gmail.com`.
3. Register `joericearchitect.com` via Route 53 and create the public hosted zone; keep the auto-created name-server records.
4. Expose the hosted-zone ID, domain name, and budget ID as Terraform outputs.

## Deliverables

- Terraform: `aws_s3_bucket` (state), `aws_dynamodb_table` (lock), `aws_budgets_budget`, `aws_route53_zone` (plus optional `aws_route53domains_registered_domain`).
- A shared `backend "s3"` remote-state configuration.

## IAM / permissions

- Performed with `jra-platform-bootstrap` (or `joe-rice-admin`); `jra-platform-terraform` is granted state/backend access in slice 01.

## Validation (exit criteria)

- `terraform init` and `terraform plan` succeed against the remote backend.
- `aws budgets describe-budget` shows the $33 cap and the gmail address.
- `aws route53 list-hosted-zones` returns the `joericearchitect.com` zone.

## Notes and risks

- Domain registration (~$14/year) and the hosted zone (~$0.50/month) are the only unavoidable Phase 1 costs; everything else should be $0 when cold.
