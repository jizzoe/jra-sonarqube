# Sources for sonarqube-aws-cost-and-public-exposure

## Amazon ECS pricing
- Publisher: AWS
- URL or path: https://aws.amazon.com/ecs/pricing/
- Access date: 2026-08-21
- Source type: primary
- Relevance: Authoritative ECS control-plane pricing.
- Classification: verified-fact
- Claim domain: pricing

## Amazon ECS launch types and capacity providers
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/capacity-launch-type-comparison.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Defines the recommended ECS EC2-capacity configuration approach.
- Classification: verified-fact
- Claim domain: technical

## Amazon EC2 T3 instances
- Publisher: AWS
- URL or path: https://aws.amazon.com/ec2/instance-types/t3/
- Access date: 2026-08-21
- Source type: primary
- Relevance: Supplies an on-demand compute baseline.
- Classification: verified-fact
- Claim domain: pricing

## Amazon RDS for PostgreSQL pricing
- Publisher: AWS
- URL or path: https://aws.amazon.com/rds/postgresql/pricing/
- Access date: 2026-08-21
- Source type: primary
- Relevance: Defines RDS bill components and HA behavior.
- Classification: verified-fact
- Claim domain: pricing

## Amazon RDS us-east-1 public price list
- Publisher: AWS
- URL or path: https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/us-east-1/index.json
- Access date: 2026-08-21
- Source type: primary
- Relevance: Live regional rate source used for the estimate.
- Classification: verified-fact
- Claim domain: pricing

## Amazon EBS pricing
- Publisher: AWS
- URL or path: https://aws.amazon.com/ebs/pricing/
- Access date: 2026-08-21
- Source type: primary
- Relevance: Supplies persistent application-volume calculation.
- Classification: verified-fact
- Claim domain: pricing

## Elastic Load Balancing pricing
- Publisher: AWS
- URL or path: https://aws.amazon.com/elasticloadbalancing/pricing/
- Access date: 2026-08-21
- Source type: primary
- Relevance: Quantifies managed HTTPS ingress tradeoff.
- Classification: verified-fact
- Claim domain: pricing

## Amazon VPC pricing
- Publisher: AWS
- URL or path: https://aws.amazon.com/vpc/pricing/
- Access date: 2026-08-21
- Source type: primary
- Relevance: Quantifies public-IP costs.
- Classification: verified-fact
- Claim domain: pricing

## Enable internet access for a VPC using an internet gateway
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/vpc/latest/userguide/VPC\_Internet\_Gateway.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Defines direct public-IP prerequisites.
- Classification: verified-fact
- Claim domain: technical

## AWS Certificate Manager public certificates
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Tests whether direct-IP access has a normal managed TLS path.
- Classification: verified-fact
- Claim domain: technical

## Amazon CloudWatch pricing
- Publisher: AWS
- URL or path: https://aws.amazon.com/cloudwatch/pricing/
- Access date: 2026-08-21
- Source type: primary
- Relevance: Identifies variable observability spend.
- Classification: source-reported-claim
- Claim domain: pricing

## Cost-comparison synthesis
- Publisher: Assistant calculation from cited AWS rates
- URL or path: https://calculator.aws/\#/createCalculator
- Access date: 2026-08-21
- Source type: secondary
- Relevance: Applies the live rates to the proposed singleton baseline.
- Classification: recommendation
- Claim domain: general
