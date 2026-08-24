output "hosted_zone_id" {
  description = "Route 53 hosted zone ID for the apex domain"
  value       = aws_route53_zone.apex.zone_id
}

output "domain_name" {
  description = "Apex domain name"
  value       = aws_route53_zone.apex.name
}

output "hosted_zone_name_servers" {
  description = "Name servers assigned to the apex hosted zone"
  value       = aws_route53_zone.apex.name_servers
}

output "budget_id" {
  description = "ID of the monthly budget alarm"
  value       = aws_budgets_budget.monthly.id
}

output "state_bucket" {
  description = "Terraform remote-state S3 bucket name"
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table" {
  description = "Terraform state-locking DynamoDB table name"
  value       = aws_dynamodb_table.terraform_lock.name
}
