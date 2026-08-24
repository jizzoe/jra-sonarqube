# ---------------------------------------------------------------------------
# Slice 01 - Secrets Manager store (resolves Q6)
# Values are set out-of-band (never in state/repo); only ARNs appear here.
# recovery_window_in_days = 0 lets the prototype delete these immediately.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "postgres_superuser" {
  name                    = "sonarqube/postgres/superuser"
  description             = "PostgreSQL superuser password (value set out-of-band)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "postgres_app" {
  name                    = "sonarqube/postgres/app"
  description             = "SonarQube PostgreSQL application user password (value set out-of-band)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "sonarqube_admin" {
  name                    = "sonarqube/admin"
  description             = "SonarQube admin password (value set out-of-band)"
  recovery_window_in_days = 0
}

output "secret_arns" {
  description = "ARNs of the three project secrets (values not in state)"
  value = {
    postgres_superuser = aws_secretsmanager_secret.postgres_superuser.arn
    postgres_app       = aws_secretsmanager_secret.postgres_app.arn
    sonarqube_admin    = aws_secretsmanager_secret.sonarqube_admin.arn
  }
}
