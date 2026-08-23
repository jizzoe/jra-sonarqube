# Slice 09 — Cost validation & rollout

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Prove the cold-off model stays under $33/month and finalize rollout.

## Prerequisites

- Slice 08 (full lifecycle working end to end).

## Steps

1. Run a full cold-start → scan → cold-stop cycle and record actual spend.
2. Verify the budget alarm fires on the expected trajectory and the cold-off floor ≈ S3 + domain + hosted zone.
3. Tune host size or retention if the $33 cap is threatened (recall `t3.large` ≈ $61/month if left on 24/7, so cold-off is the control).
4. Record the done criteria and hand off to the Phase 2 public-DNS/ingress brief.

## Deliverables

- Cost runbook with measurements, final sizing, rollout sign-off.

## Validation (exit criteria)

- A representative month projects ≤ $33 with cold-off; alarm and teardown are verified.

## Notes and risks

- If actuals exceed the cap, revisit host size (`t3.medium`) or session length before starting Phase 2.
