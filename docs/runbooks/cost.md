# SonarQube ECS — cost runbook

Purpose: prove the cold-off model stays under the **$33/month** budget cap and
record how to re-measure it.

## Model — cold off by default

### Always-on ("cold-off floor")

| Component | Cost |
| --- | --- |
| Route 53 public hosted zone (`joericearchitect.com`) | $0.50/month |
| S3 dumps + state (~30 MB) | < $0.01/month |
| CloudWatch Logs (minimal usage) | ~ $0.00 |
| **Cold-off floor** | **≈ $0.51/month** |

Domain registration (~$14/year) is deferred to a third-party registrar and is
outside AWS.

### Working session (host up, per hour)

| Component | Cost |
| --- | --- |
| EC2 `m7i-flex.large` (2 vCPU / 8 GiB) | ~ $0.08/hr |
| Public IPv4 (auto-assigned; released on stop) | $0.005/hr |
| 30 GiB gp3 EBS (delete-on-termination) | ~ $0.003/hr |
| **Session total** | **≈ $0.09/hr** |

### Representative month

10 sessions × 2 hours = 20 hours × $0.09 = $1.80, plus the $0.51 floor ≈
**$2.31/month** (~14× under the cap).

> Control check: leaving the host on 24/7 is ≈ $65–70/month. **Cold-off is the
> control that keeps this under $33.**

## Verification commands (us-east-1, `jra-platform-terraform`)

```bash
# Budget config + health
aws --profile jra-platform-terraform budgets describe-budget \
  --account-id 389633344341 --budget-name sonarqube-monthly-budget

# Notification (alarm trigger)
aws --profile jra-platform-terraform budgets describe-notifications-for-budget \
  --account-id 389633344341 --budget-name sonarqube-monthly-budget

# Subscriber (email)
aws --profile jra-platform-terraform budgets describe-subscribers-for-notification \
  --account-id 389633344341 --budget-name sonarqube-monthly-budget \
  --notification NotificationType=ACTUAL,ComparisonOperator=GREATER_THAN,Threshold=100

# Backup storage usage
aws --profile jra-platform-terraform s3 ls s3://jra-sonarqube-dumps --recursive --summarize

# Confirm cold-off (should be 0 instances / no running EC2)
aws --profile jra-platform-terraform ec2 describe-instances \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId'
```

## Re-measurement

- **Actual spend:** AWS Cost Explorer (`aws ce get-cost-and-usage`) lags ~24h and
  requires Cost Explorer activation; while the account is under the $200/6-month
  credit, `CalculatedSpend.ActualSpend` may report $0.00. Check the Billing
  console / CE after a full cycle.
- **Rates:** re-run the AWS Pricing Calculator before any sizing change; the
  figures above are rate-card estimates.

## Tune / revisit triggers

- If a month approaches $33: shorten sessions, or move `m7i-flex.large` →
  `t3.medium` once the Free Tier restriction lifts.
- Retention is already a 90-day S3 lifecycle on the `sonar-` prefix
  (`backup.tf`).
- Phase 2 adds an on-demand Elastic IP ($0.005/hr, released on shutdown) — keep
  the same cold-off discipline.

## Sign-off

Phase 1 rollout signed off (2026-08-24): cold-off floor ≈ $0.51/month,
representative month ≈ $2.31/month ≤ $33; budget alarm and teardown verified.
Proceed to Phase 2 (public DNS/ingress).
