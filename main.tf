# ---------------------------------------------------------------------------
# Slice 00 - Account foundations
# Terraform state backend (S3 + DynamoDB), budget alarm, and Route 53 apex
# domain hosted zone. Shared by Phase 1 and the Phase 2 public-ingress add-on.
# ---------------------------------------------------------------------------

# Terraform state storage (versioned, encrypted, private)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "jra-sonarqube-terraform-state"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State-locking table
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "jra-sonarqube-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# $33/month budget alarm -> email
resource "aws_budgets_budget" "monthly" {
  name              = "sonarqube-monthly-budget"
  budget_type       = "COST"
  limit_amount      = var.budget_limit
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = var.budget_time_period_start

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

# Apex domain public hosted zone (NS + SOA records auto-created)
resource "aws_route53_zone" "apex" {
  name = var.domain
}
