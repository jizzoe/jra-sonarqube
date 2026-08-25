# ---------------------------------------------------------------------------
# Phase 2 - public DNS/ingress (durable host-side config)
# The Elastic IP, DNS A record, and TLS proxy are ephemeral and lifecycle-
# managed by the orchestration scripts (allocate/release, upsert/delete,
# start/stop), so only the durable IAM grant lives here: the ECS host role
# needs Route 53 DNS-01 access so Caddy can obtain and renew a Let's Encrypt
# certificate for the public hostname.
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "ecs_host_route53_dns01" {
  name = "ecs-host-route53-dns01"
  role = aws_iam_role.ecs_host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
        ]
        Resource = [aws_route53_zone.apex.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = ["arn:aws:route53:::change/*"]
      },
    ]
  })
}
