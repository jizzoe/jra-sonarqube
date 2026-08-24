# ---------------------------------------------------------------------------
# Slice 06 - Backup & shutdown gate (resolves Q5, Option A)
# Encrypted S3 dump bucket + host access + 90-day retention.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "dumps" {
  bucket = "jra-sonarqube-dumps"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dumps" {
  bucket = aws_s3_bucket.dumps.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dumps" {
  bucket = aws_s3_bucket.dumps.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "dumps" {
  bucket = aws_s3_bucket.dumps.id

  rule {
    id     = "expire-old-dumps"
    status = "Enabled"

    filter {
      prefix = "sonar-"
    }

    expiration {
      days = 90
    }
  }
}

# The backup/restore scripts run on the host (via SSM / orchestration), so the
# host role needs access to the dumps bucket.
resource "aws_iam_role_policy" "ecs_host_s3_dumps" {
  name = "ecs-host-s3-dumps"
  role = aws_iam_role.ecs_host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.dumps.arn,
          "${aws_s3_bucket.dumps.arn}/*",
        ]
      },
    ]
  })
}
