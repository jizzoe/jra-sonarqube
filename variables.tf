variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile used to authenticate (least-privilege Terraform role)"
  type        = string
  default     = "jra-platform-terraform"
}

variable "domain" {
  description = "Apex domain for the Route 53 public hosted zone"
  type        = string
  default     = "joericearchitect.com"
}

variable "budget_limit" {
  description = "Monthly budget cap in USD"
  type        = number
  default     = 33
}

variable "budget_email" {
  description = "Email address for budget alerts"
  type        = string
  default     = "joericearchitect@gmail.com"
}

variable "budget_time_period_start" {
  description = "Start of the monthly budget time period (UTC), format YYYY-MM-DD_HH:MM"
  type        = string
  default     = "2026-08-01_00:00"
}

variable "host_instance_type" {
  description = "ECS host instance type. m7i-flex.large (2 vCPU / 8 GiB) is free-tier eligible; t3.large (same size) is blocked on free-tier accounts."
  type        = string
  default     = "m7i-flex.large"
}
