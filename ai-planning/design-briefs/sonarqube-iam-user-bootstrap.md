# JRA platform IAM bootstrap design brief

## 1. Problem and desired outcome

The AWS account will host several applications over time: SonarQube, a mobile-app backend, and possibly Jenkins. It needs a secure human entry point for account setup and Terraform without creating one long-lived IAM user per application.

The selected model is one MFA-protected human IAM user, `joe-rice-admin`, with temporary CLI credentials. Application and automation access is provided by separate IAM roles:

```text
joe-rice-admin (human Console/CLI identity)
        |
        +--> jra-platform-bootstrap (temporary broad bootstrap role)
        +--> jra-platform-terraform (normal Terraform role)
        +--> jra-sonarqube-deploy
        +--> jra-mobile-backend-deploy

ECS/runtime roles are separate:
  jra-sonarqube-task
  jra-mobile-backend-task

Jenkins roles are intentionally deferred until Jenkins is actually introduced.
```

## 2. Evidence and key findings

The following durable research supports this decision:

- [IAM user bootstrap findings](../research/infrastructure/sonarqube-iam-user-bootstrap/sonarqube-iam-user-bootstrap-findings.md) — current AWS IAM, Billing, and CLI authentication guidance.
- [IAM bootstrap sources](../research/infrastructure/sonarqube-iam-user-bootstrap/sources.md) — official AWS and HashiCorp source provenance.
- [SonarQube prototype design brief](sonarqube-single-user-ecs-prototype.md) — the first application and its cold-off runtime requirements.

Key findings:

- AWS recommends temporary credentials and MFA for human access. `aws login` can provide temporary credentials for a console-enabled IAM user; long-lived access keys are unnecessary.
- Applications and ECS tasks should use roles with only their own permissions. ECS recommends separate task roles for services and supports auditability through task-scoped credentials.
- Terraform should use an external profile or role and must not embed credentials in `.tf` files, variables, state, or source control.
- The account is intended to remain standalone while Free Tier eligibility is evaluated; creating or joining Organizations would change that billing assumption and requires a separate decision.

## 3. Options considered and tradeoffs

| Option | Impact and tradeoff |
| --- | --- |
| One human `joe-rice-admin` user plus platform and app roles | **Recommended.** Simple for one owner, separates human access from workload access, and scales to more apps without creating more human credentials. |
| One IAM user per app (`sonarqube-admin`, `mobile-admin`, `jenkins-admin`) | Rejected. Duplicates human credentials, increases audit and rotation burden, and incorrectly couples a person to an application. |
| IAM Identity Center as the human identity system | AWS-preferred long term, but adds account/identity-center setup and may affect the current Free Tier strategy. Revisit if this becomes a multi-person or multi-account environment. |
| Root identity or long-lived access keys | Rejected. Root is for one-time account tasks only; workloads and Terraform use temporary role credentials. |

## 4. Decisions, assumptions, and owner

- Owner: repository owner.
- User-confirmed direction: use exactly one human `joe-rice-admin` IAM user; use platform and application roles; create no Jenkins role until Jenkins is needed.
- Human profile: `joe-rice-admin`, Console access, MFA, no access keys, and `aws login --profile joe-rice-admin`.
- Temporary bootstrap role: `jra-platform-bootstrap`, initially able to perform account bootstrap and role creation. Its broad permissions are temporary and must be reviewed or removed.
- Normal Terraform role: `jra-platform-terraform`, scoped to the approved Terraform resource inventory and state/backend operations.
- Current application roles: `jra-sonarqube-deploy` and `jra-mobile-backend-deploy`.
- Current ECS runtime roles: `jra-sonarqube-task` and `jra-mobile-backend-task`, each limited to its own service needs.
- Deferred role: do not create `jra-jenkins-deploy` or any Jenkins runtime role until Jenkins is actually introduced and its execution model is selected.
- Formal approval evidence: no digest-bound confirmation was supplied; this records the user's explicit direction but is not a cryptographic approval receipt.
- Assumptions: this is a standalone personal account, root MFA can be used for one-time security and Billing activation, and no sensitive values will be placed in chat, shell history, Terraform, state, or the repository.

### Permission-set matrix

| Identity or policy | Status | Purpose |
| --- | --- | --- |
| Root-user MFA | Required before bootstrap | Protect the account owner; root is never used for normal CLI/Terraform work. |
| `joe-rice-admin` console password + MFA | Required | Human Console access and temporary `aws login` credentials. |
| `AdministratorAccess` on `joe-rice-admin` | Temporary only | Bootstrap the first roles and account controls before the exact resource inventory is known. |
| `SignInLocalDevelopmentAccess` | Required for ongoing `aws login` after broad admin is removed | Enables the AWS Sign-in OAuth flow. |
| `AWSBillingReadOnlyAccess` | Optional after bootstrap | Provides separated cost visibility if a read-only billing profile is desired. |
| `jra-platform-bootstrap` | Temporary role | Broad bootstrap operations, assumable by the human profile. |
| `jra-platform-terraform` | Normal Terraform role | Custom least-privilege permissions for the approved platform/resource inventory. |
| `jra-sonarqube-deploy` | Create for SonarQube | Deployment permissions limited to SonarQube resources. |
| `jra-mobile-backend-deploy` | Create for mobile backend | Deployment permissions limited to mobile-backend resources. |
| `jra-jenkins-deploy` | **Do not create yet** | Add only when Jenkins exists and its CI trust model is selected. |
| `jra-sonarqube-task` / `jra-mobile-backend-task` | Create with each ECS service | Runtime permissions for the individual container; never use a human or Terraform role in a task. |

## 5. Scope, non-goals, constraints, dependencies, and risks

### Scope

- Root-account hardening and one-time Billing-console IAM access activation.
- Creating and securing `joe-rice-admin` with MFA and no access keys.
- Creating the temporary platform bootstrap role and named CLI profiles.
- Defining the Terraform role and current application/runtime role boundaries.
- Documenting the migration from temporary bootstrap administration to scoped Terraform and application roles.

### Non-goals

- Creating Jenkins roles before Jenkins is needed.
- Giving SonarQube, the mobile backend, ECS tasks, or future CI systems the human user's permissions.
- Creating infrastructure resources, Terraform state, or access keys in this brief.
- Enabling AWS Organizations or IAM Identity Center without a separate Free Tier and account-governance decision.

### Constraints and dependencies

- Install AWS CLI v2.32.0 or later. Use a passkey/security key or authenticator MFA device.
- Keep Terraform credentials external to the repository and use named profiles explicitly.
- Use IAM roles for ECS task/runtime permissions and add resource-specific policies only after the application resource inventory is known.
- Create `jra-jenkins-deploy` only after Jenkins hosting, trust source, and required AWS APIs are documented.

### Risks and controls

- **Bootstrap blast radius:** temporary AdministratorAccess can change the entire account. Mitigate with MFA, no access keys, a short review window, and removal or restriction after role creation.
- **Role sprawl:** adding an app role before the app exists creates unused privilege. Create roles only when their workload is real.
- **Shared account impact:** an overly broad Terraform role could change every application. Scope it by resource/tag boundaries where practical and review plans before apply.
- **EC2 ECS exposure:** containers on ECS EC2 are not the same isolation boundary as Fargate. Use separate task roles and restrict container access to EC2 instance metadata.

### Manual prerequisite runbook

Complete these steps before authorizing infrastructure creation. Never send passwords, MFA codes, cookies, access keys, or secret keys to an assistant.

#### A. One-time root-user console steps

1. Sign in to the new AWS account as root only for setup.
2. Enable root MFA using a passkey/security key or authenticator.
3. In Billing and Cost Management, activate IAM user and role access to Billing information if needed.
4. Do not create root access keys. Sign out of root after these steps.

#### B. Create the human identity

1. In IAM → Users, create the user named `joe-rice-admin`.
2. Enable AWS Management Console access and set a strong unique password.
3. Attach `AdministratorAccess` temporarily for bootstrap. Do not attach app-specific policies to this human user.
4. Assign MFA immediately and confirm there are zero active access keys.
5. Sign in as `joe-rice-admin` and use that identity for all subsequent setup.

#### C. Create the temporary bootstrap profile

```zsh
aws --version
aws login --profile joe-rice-admin
aws sts get-caller-identity --profile joe-rice-admin
aws configure list --profile joe-rice-admin
```

Create `jra-platform-bootstrap` as an IAM role trusted only by `joe-rice-admin`, attach the temporary bootstrap permissions, and add a local role profile in `~/.aws/config`:

```ini
[profile jra-platform-bootstrap]
role_arn = arn:aws:iam::<account-id>:role/jra-platform-bootstrap
source_profile = joe-rice-admin
region = us-east-1
```

Use `AWS_PROFILE=jra-platform-bootstrap` for bootstrap CLI commands. Do not put the account ID or credentials in the repository.

#### D. Establish the normal Terraform and application boundaries

1. Create `jra-platform-terraform` with a custom policy derived from the approved Terraform resource inventory. Include only platform resources, state/backend operations, and the ability to pass the specific ECS/EC2 roles it creates.
2. Configure a local profile that assumes `jra-platform-terraform` from `joe-rice-admin` or the bootstrap profile.
3. Create `jra-sonarqube-deploy`, `jra-sonarqube-task`, `jra-mobile-backend-deploy`, and `jra-mobile-backend-task` as each application is designed.
4. Do not create `jra-jenkins-deploy` or Jenkins runtime roles yet.
5. After the Terraform role is validated, remove `AdministratorAccess` from `joe-rice-admin` or restrict the user to assuming the approved roles.

#### E. Terraform profile usage

Use a named role profile rather than embedding provider credentials:

```zsh
export AWS_PROFILE=jra-platform-terraform
export AWS_REGION=us-east-1
terraform init
terraform plan
```

If a tool does not consume the AWS CLI login profile directly, use a local `credential_process` profile in `~/.aws/config`; never store it in the repository. Renew the human login with `aws login --profile joe-rice-admin` when the session expires.

## 6. Open questions and blocking decisions

1. Is `us-east-1` the final deployment region for all three planned applications?
2. What monthly budget cap and notification address should the platform create before the first runtime resource?
3. Which exact Terraform resources and IAM service roles belong in `jra-platform-terraform`?
4. What DNS, secrets, and backup resources should be scoped to `jra-sonarqube-deploy` versus the platform role?
5. When Jenkins is introduced, will it run on ECS, EC2, or an external CI system, and will it use OIDC or an assumed role?

## 7. Recommended next step

Create and secure `joe-rice-admin`, establish `jra-platform-bootstrap`, and use the bootstrap role to finalize the Terraform resource inventory and policy. Then create `jra-platform-terraform` and the SonarQube/mobile application roles. Defer all Jenkins IAM resources until Jenkins is actually selected and its trust model is known. No OpenSpec artifacts were created by this brief.
