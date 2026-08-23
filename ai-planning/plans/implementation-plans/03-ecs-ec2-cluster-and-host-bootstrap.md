# Slice 03 — ECS cluster (EC2) & host bootstrap

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Stand up the ECS cluster on EC2 capacity and bake SonarQube's Linux prerequisites into host boot.

## Prerequisites

- Slice 02 (VPC, security groups, SSM endpoints, instance profile).

## Steps

1. Create the ECS cluster with an EC2 Auto Scaling group capacity provider (never Fargate or ECS Managed Instances).
2. Create a launch template using `t3.large`, the SSM instance profile, and a supported x86 AMI.
3. Add user-data that sets `vm.max_map_count=262144` and file-descriptor/process ulimits before the ECS agent starts.
4. Set the capacity provider and a target capacity of 1; confirm the agent registers an instance.

## Deliverables

- `aws_ecs_cluster`, `aws_ecs_capacity_provider`, `aws_autoscaling_group`, `aws_launch_template`, `user_data` (sysctls/ulimits).

## Validation (exit criteria)

- `aws ecs list-container-instances` returns one registered instance with an active agent.
- Via Session Manager, `cat /proc/sys/vm/max_map_count` on the host returns `262144`.

## Notes and risks

- `t3.large` is the default (2 vCPU / 8 GiB); sustained CPU above baseline can incur Unlimited-mode credit charges — keep scans on demand.
