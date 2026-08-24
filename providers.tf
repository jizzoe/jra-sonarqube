terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "jra-sonarqube-terraform-state"
    key            = "sonarqube/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "jra-sonarqube-terraform-lock"
    encrypt        = true
    profile        = "terraform"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
