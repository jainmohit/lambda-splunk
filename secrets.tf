# Data sources to read existing secrets if create_*_secret is false
data "aws_secretsmanager_secret" "existing_api_credentials" {
  count = var.create_api_secret ? 0 : 1
  name  = var.api_credentials_secret_name
}

# Create new API credentials secret only if create_api_secret is true
resource "aws_secretsmanager_secret" "api_credentials" {
  count       = var.create_api_secret ? 1 : 0
  name        = var.api_credentials_secret_name
  description = "API authentication credentials for cron job"
  
  tags = {
    Purpose     = "API Cron Job - Authentication"
    Environment = "production"
    SecretType  = "api-credentials"
  }
}

# Use the appropriate secret ARNs based on whether we created them or they exist
locals {
  api_credentials_secret_arn    = var.create_api_secret ? aws_secretsmanager_secret.api_credentials[0].arn : data.aws_secretsmanager_secret.existing_api_credentials[0].arn
}
