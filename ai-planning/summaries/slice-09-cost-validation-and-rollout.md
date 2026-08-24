# Slice 09 — Cost validation & rollout — slice summary

Status: ✅ complete (2026-08-24)

## Goal

Prove the cold-off model stays under $33/month and finalize rollout.

## Measurements (recorded 2026-08-24)

- Budget `sonarqube-monthly-budget`: **$33.00/mo**, COST, MONTHLY, HEALTHY.
- Notification: `ACTUAL` / `GREATER_THAN` / `100%` / `OK` → EMAIL
  `joericearchitect@gmail.com` (verified via `describe-notifications-for-budget`
  and `describe-subscribers-for-notification`).
- `CalculatedSpend.ActualSpend` = **$0.00** (account is under the $200/6-month
  credit; Cost Explorer has lag — re-check after 24–48h).
- S3 dumps bucket: 7 objects, **~29.6 MB** total (≈ < $0.01/month).
- Cold-off verified: ASG desired 0, **0 running instances**, EBS destroyed.

## Cost model (us-east-1 rate card)

| Component | Cost |
| --- | --- |
| Route 53 hosted zone (`joericearchitect.com`) | $0.50/month |
| S3 dumps + state (~30 MB) | < $0.01/month |
| CloudWatch Logs (minimal) | ~ $0.00 |
| **Cold-off floor** | **≈ $0.51/month** |

| Session component (host up) | Cost |
| --- | --- |
| EC2 `m7i-flex.large` (2 vCPU / 8 GiB) | ~ $0.08/hr |
| Public IPv4 (auto-assigned, released on stop) | $0.005/hr |
| 30 GiB gp3 EBS (delete-on-termination) | ~ $0.003/hr |
| **Session total** | **≈ $0.09/hr** |

Representative month (10 × 2-hour sessions): $1.80 + floor $0.51 ≈
**$2.31/month** (~14× under cap). Control check: 24/7 ≈ $65–70/month, so
cold-off is the required control.

## Final sizing

`m7i-flex.large` (free-tier eligible; `t3.large` blocked on the Free Tier
account). No change needed at the measured usage.

## Deliverables

- `docs/runbooks/cost.md` — cost runbook with measurements and commands.
- Rollout sign-off: budget alarm + teardown verified.

## Validation (exit criteria)

A representative month projects ≤ $33 with cold-off ✅; budget alarm ✅;
teardown ✅.

## Handoff

Phase 2 (public DNS/ingress) — see
`ai-planning/design-briefs/sonarqube-public-dns-ingress.md`. Open question:
TLS method (Let's Encrypt vs ACM exportable).
