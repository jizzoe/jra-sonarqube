# Slice 02 — VPC, network, and access

Part of: [roadmap](../roadmaps/sonarqube-single-user-ecs-prototype-roadmap.md) · Brief: [sonarqube-single-user-ecs-prototype.md](../../design-briefs/sonarqube-single-user-ecs-prototype.md)

## Goal

Provision the private network and the Session Manager administration path with no public inbound.

## Prerequisites

- Slice 01 (roles exist to assume/use).

## Steps

1. Create the VPC, a public subnet, an internet gateway, and routes (outbound only).
2. Define security groups with default-deny: allow port 9000 only from the application security group; allow nothing public. No inbound 443 or 22.
3. Add VPC endpoints for SSM (`ssm`, `ec2messages`, `ssmmessages`) so Session Manager works without a public IP.
4. Create the ECS host instance profile with `AmazonSSMManagedInstanceCore`.

## Deliverables

- `aws_vpc`, `aws_subnet`, `aws_internet_gateway`, `aws_route_table`, `aws_security_group`, `aws_vpc_endpoint` (SSM family), `aws_iam_instance_profile`.

## Validation (exit criteria)

- A test instance is reachable via `aws ssm start-session` yet exposes no public IP or ports.

## Notes and risks

- NAT gateway is explicitly out of scope (cost); outbound uses the internet gateway, and S3 traffic can use an S3 gateway endpoint.
