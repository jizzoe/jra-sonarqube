# sonarqube-iam-user-bootstrap research findings

Depth: standard

## Summary
Summary: Current AWS IAM and CLI evidence for a manually created, MFA-protected sonarqube-admin IAM user and named local profile that can bootstrap this single-user Terraform deployment without long-lived access keys.

## Verified facts
- AWS recommends federation and temporary credentials for human users and workloads, requiring MFA, applying least privilege, using IAM Access Analyzer, and regularly reviewing unused credentials and permissions. If IAM users are necessary, AWS recommends MFA, preferably phishing-…
- IAM users can have a console password and/or access keys. IAM users with console access can use those credentials to authenticate to the AWS CLI and SDKs through aws login. AWS recommends MFA for all IAM users and removal of passwords and access keys that are no longer needed.
- AWS CLI 2.32.0 or later can use aws login with AWS Management Console credentials, including an IAM user. The login creates temporary credentials, refreshes them during the session for up to 12 hours, and supports named profiles with aws login --profile. An IAM identity using th…
- The AWS managed policy SignInLocalDevelopmentAccess grants signin:AuthorizeOAuth2Access and signin:CreateOAuth2Token for public OAuth clients, enabling programmatic access through the AWS Sign-in service. It can be attached to users, groups, and roles.
- AWS recommends console-credential login with short-term credentials for root, IAM users, or federation; IAM Identity Center is the workforce best practice. IAM roles and instance profiles provide temporary credentials for AWS workloads. Long-lived IAM-user credentials are not re…
- IAM users and roles cannot access the Billing and Cost Management console by default. The AWS account root user must activate IAM access once per account. This console setting does not control Billing SDK APIs such as Cost Explorer and Budgets APIs.
- AWSBillingReadOnlyAccess is an AWS managed policy that grants read-only access to Billing and Cost Management console features, including account and aws-portal read-only permissions.
- Terraform providers need cloud credentials. The AWS provider supports shared credentials files, shared configuration files, environment variables, container credentials, and instance profiles. HashiCorp warns not to place provider credentials in Terraform configuration because t…

## Source-reported claims
- None supplied.

## Assistant inferences
- AWS CLI profiles can assume an IAM role using source credentials. The role must trust the source identity and have policies permitting requested actions. A role trust policy can require MFA, and temporary role credentials are cached until expiration.

## Unknowns
- None supplied.

## Recommendations
- AWS recommends no root access keys and prefers temporary credentials and MFA. If IAM-user access keys are unavoidable, they should receive only the permissions required and be audited and removed when unused.

## Model guidance provenance
- Role: balanced-standard
- Lookup date: 2026-08-21
- codex: gpt-5.6-terra; source: https://developers.openai.com/codex/models; stale-risk; verify current official provider documentation before use

## Use cases
- See the classified findings and linked sources above.

## SDLC fit
- See the classified findings and linked sources above.

## Open-source and paid options
- See the classified findings and linked sources above.

## Tutorials and articles
- See the classified findings and linked sources above.

## Project fit
- See the classified findings and linked sources above.

## Source material used as data
### Security best practices in IAM
> AWS recommends federation and temporary credentials for human users and workloads, requiring MFA, applying least privilege, using IAM Access Analyzer, and regularly reviewing unused credentials and permissions. If IAM users are necessary, AWS recommends MFA, preferably phishing-…

### IAM users
> IAM users can have a console password and/or access keys. IAM users with console access can use those credentials to authenticate to the AWS CLI and SDKs through aws login. AWS recommends MFA for all IAM users and removal of passwords and access keys that are no longer needed.

### Login for AWS local development using console credentials
> AWS CLI 2.32.0 or later can use aws login with AWS Management Console credentials, including an IAM user. The login creates temporary credentials, refreshes them during the session for up to 12 hours, and supports named profiles with aws login --profile. An IAM identity using th…

### SignInLocalDevelopmentAccess managed policy
> The AWS managed policy SignInLocalDevelopmentAccess grants signin:AuthorizeOAuth2Access and signin:CreateOAuth2Token for public OAuth clients, enabling programmatic access through the AWS Sign-in service. It can be attached to users, groups, and roles.

### Authentication and access credentials for the AWS CLI
> AWS recommends console-credential login with short-term credentials for root, IAM users, or federation; IAM Identity Center is the workforce best practice. IAM roles and instance profiles provide temporary credentials for AWS workloads. Long-lived IAM-user credentials are not re…

### Overview of managing access permissions for Billing
> IAM users and roles cannot access the Billing and Cost Management console by default. The AWS account root user must activate IAM access once per account. This console setting does not control Billing SDK APIs such as Cost Explorer and Budgets APIs.

### AWS managed policies for Billing
> AWSBillingReadOnlyAccess is an AWS managed policy that grants read-only access to Billing and Cost Management console features, including account and aws-portal read-only permissions.

### Secure access keys
> AWS recommends no root access keys and prefers temporary credentials and MFA. If IAM-user access keys are unavoidable, they should receive only the permissions required and be audited and removed when unused.

### Using an IAM role in the AWS CLI
> AWS CLI profiles can assume an IAM role using source credentials. The role must trust the source identity and have policies permitting requested actions. A role trust policy can require MFA, and temporary role credentials are cached until expiration.

### Configure Terraform providers
> Terraform providers need cloud credentials. The AWS provider supports shared credentials files, shared configuration files, environment variables, container credentials, and instance profiles. HashiCorp warns not to place provider credentials in Terraform configuration because t…
