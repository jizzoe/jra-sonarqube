# Sources for sonarqube-iam-user-bootstrap

## Security best practices in IAM
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Establishes MFA, temporary credentials, least privilege, and human-identity best practices.
- Classification: verified-fact
- Claim domain: policy

## IAM users
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/IAM/latest/UserGuide/id\_users.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Defines console passwords, access keys, MFA, and use of aws login with IAM user console credentials.
- Classification: verified-fact
- Claim domain: policy

## Login for AWS local development using console credentials
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Provides the temporary-credential workflow for AWS CLI local login and named profiles.
- Classification: verified-fact
- Claim domain: technical

## SignInLocalDevelopmentAccess managed policy
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/aws-managed-policy/latest/reference/SignInLocalDevelopmentAccess.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Defines the managed policy needed by an IAM user to use aws login.
- Classification: verified-fact
- Claim domain: policy

## Authentication and access credentials for the AWS CLI
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Ranks the recommended AWS CLI authentication choices and documents roles and instance profiles.
- Classification: verified-fact
- Claim domain: technical

## Overview of managing access permissions for Billing
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/control-access-billing.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Defines the root-only, one-time Billing console access activation needed for IAM users and roles.
- Classification: verified-fact
- Claim domain: policy

## AWS managed policies for Billing
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/managed-policies.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Defines the AWSBillingReadOnlyAccess managed policy for cost visibility.
- Classification: verified-fact
- Claim domain: policy

## Secure access keys
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/IAM/latest/UserGuide/securing-access-keys.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Supports avoiding root and long-lived IAM-user access keys.
- Classification: recommendation
- Claim domain: policy

## Using an IAM role in the AWS CLI
- Publisher: AWS
- URL or path: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html
- Access date: 2026-08-21
- Source type: primary
- Relevance: Provides the long-term migration model from IAM user to an MFA-protected assumed role.
- Classification: assistant-inference
- Claim domain: technical

## Configure Terraform providers
- Publisher: HashiCorp
- URL or path: https://developer.hashicorp.com/terraform/tutorials/configuration-language/configure-providers
- Access date: 2026-08-21
- Source type: primary
- Relevance: Establishes Terraform AWS provider support for shared configuration and credential sources and warns against credentials in version control.
- Classification: verified-fact
- Claim domain: technical
