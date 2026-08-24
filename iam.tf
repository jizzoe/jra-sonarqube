# ---------------------------------------------------------------------------
# Slice 01 - IAM workload roles
# Least-privilege roles: platform Terraform, SonarQube deploy, and the
# SonarQube ECS task runtime. Secret values live in Secrets Manager (Q6);
# only ARN references appear here and in state.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_user" "admin" {
  user_name = "joe-rice-admin"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.aws_region
}

# --- jra-platform-terraform: normal least-privilege Terraform role ---
resource "aws_iam_role" "platform_terraform" {
  name = "jra-platform-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = data.aws_iam_user.admin.arn }
        Action    = "sts:AssumeRole"
      },
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:role/jra-platform-bootstrap" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  inline_policy {
    name = "platform-terraform"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["ec2:*", "ecs:*", "autoscaling:*", "cloudwatch:*"]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:ListBucket",
            "s3:GetBucketLocation",
            "s3:GetBucketVersioning",
            "s3:GetEncryptionConfiguration",
            "s3:PutEncryptionConfiguration",
            "s3:PutBucketVersioning",
            "s3:PutBucketPublicAccessBlock",
            "s3:CreateBucket",
            "s3:DeleteBucket",
          ]
          Resource = "arn:aws:s3:::jra-sonarqube-*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:GetObjectVersion",
            "s3:ListBucketVersions",
          ]
          Resource = [
            "arn:aws:s3:::jra-sonarqube-*",
            "arn:aws:s3:::jra-sonarqube-*/*",
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "dynamodb:CreateTable",
            "dynamodb:DeleteTable",
            "dynamodb:DescribeTable",
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:DeleteItem",
            "dynamodb:UpdateItem",
            "dynamodb:ListTables",
          ]
          Resource = "arn:aws:dynamodb:${local.region}:${local.account_id}:table/jra-sonarqube-*"
        },
        {
          Effect = "Allow"
          Action = [
            "route53:CreateHostedZone",
            "route53:DeleteHostedZone",
            "route53:GetHostedZone",
            "route53:ListHostedZones",
            "route53:ListHostedZonesByName",
            "route53:ListResourceRecordSets",
            "route53:ChangeResourceRecordSets",
            "route53:GetChange",
          ]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = ["budgets:ViewBudget", "budgets:ModifyBudget"]
          Resource = "arn:aws:budgets::${local.account_id}:budget/*"
        },
        {
          Effect = "Allow"
          Action = [
            "secretsmanager:CreateSecret",
            "secretsmanager:UpdateSecret",
            "secretsmanager:DeleteSecret",
            "secretsmanager:DescribeSecret",
            "secretsmanager:GetSecretValue",
            "secretsmanager:PutSecretValue",
            "secretsmanager:GetResourcePolicy",
            "secretsmanager:TagResource",
          ]
          Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:sonarqube/*"
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:ListSecrets"]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:DeleteLogGroup",
            "logs:DescribeLogGroups",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:PutRetentionPolicy",
          ]
          Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*"
        },
        {
          Effect = "Allow"
          Action = ["iam:PassRole"]
          Resource = [
            "arn:aws:iam::${local.account_id}:role/jra-sonarqube-task",
            "arn:aws:iam::${local.account_id}:role/jra-sonarqube-deploy",
            "arn:aws:iam::${local.account_id}:role/jra-ecs-host-*",
            "arn:aws:iam::${local.account_id}:role/jra-ecs-task-execution-*",
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "iam:GetRole",
            "iam:GetRolePolicy",
            "iam:ListRolePolicies",
            "iam:ListAttachedRolePolicies",
            "iam:CreateRole",
            "iam:DeleteRole",
            "iam:PutRolePolicy",
            "iam:DeleteRolePolicy",
            "iam:AttachRolePolicy",
            "iam:DetachRolePolicy",
            "iam:CreateInstanceProfile",
            "iam:DeleteInstanceProfile",
            "iam:GetInstanceProfile",
            "iam:ListInstanceProfiles",
            "iam:AddRoleToInstanceProfile",
            "iam:RemoveRoleFromInstanceProfile",
          ]
          Resource = "arn:aws:iam::${local.account_id}:role/jra-*"
        },
        {
          Effect   = "Allow"
          Action   = ["iam:CreateServiceLinkedRole", "iam:ListRoles"]
          Resource = "*"
        },
      ]
    })
  }
}

# --- jra-sonarqube-deploy: deployment-only role for the SonarQube lifecycle ---
resource "aws_iam_role" "sonarqube_deploy" {
  name = "jra-sonarqube-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.platform_terraform.arn }
        Action    = "sts:AssumeRole"
      },
      {
        Effect    = "Allow"
        Principal = { AWS = data.aws_iam_user.admin.arn }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  inline_policy {
    name = "sonarqube-deploy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ecs:RunTask",
            "ecs:StopTask",
            "ecs:DescribeTasks",
            "ecs:DescribeServices",
            "ecs:UpdateService",
            "ecs:ListTasks",
            "ecs:ListServices",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "ec2:DescribeInstances",
            "ec2:DescribeInstanceStatus",
            "ec2:StartInstances",
            "ec2:StopInstances",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:ListBucket",
            "s3:GetBucketLocation",
          ]
          Resource = [
            "arn:aws:s3:::jra-sonarqube-*",
            "arn:aws:s3:::jra-sonarqube-*/*",
          ]
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:sonarqube/*"
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ]
          Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*"
        },
        {
          Effect   = "Allow"
          Action   = ["iam:PassRole"]
          Resource = [aws_iam_role.sonarqube_task.arn]
        },
      ]
    })
  }
}

# --- jra-sonarqube-task: runtime role for the ECS task ---
resource "aws_iam_role" "sonarqube_task" {
  name = "jra-sonarqube-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  inline_policy {
    name = "sonarqube-task"
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
            "s3:GetBucketLocation",
          ]
          Resource = [
            "arn:aws:s3:::jra-sonarqube-*",
            "arn:aws:s3:::jra-sonarqube-*/*",
          ]
        },
        {
          Effect = "Allow"
          Action = ["secretsmanager:GetSecretValue"]
          Resource = [
            aws_secretsmanager_secret.postgres_superuser.arn,
            aws_secretsmanager_secret.postgres_app.arn,
            aws_secretsmanager_secret.sonarqube_admin.arn,
          ]
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ]
          Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*"
        },
      ]
    })
  }
}

output "platform_terraform_role_arn" {
  description = "ARN of the jra-platform-terraform role"
  value       = aws_iam_role.platform_terraform.arn
}

output "sonarqube_deploy_role_arn" {
  description = "ARN of the jra-sonarqube-deploy role"
  value       = aws_iam_role.sonarqube_deploy.arn
}

output "sonarqube_task_role_arn" {
  description = "ARN of the jra-sonarqube-task role"
  value       = aws_iam_role.sonarqube_task.arn
}
