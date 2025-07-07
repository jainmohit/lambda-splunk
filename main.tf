# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "api_endpoint" {
  description = "API endpoint to call"
  type        = string
}

variable "cron_schedule" {
  description = "Cron schedule expression"
  type        = string
  default     = "rate(5 minutes)" # Run every 5 minutes
}

variable "auth_endpoint" {
  description = "Authentication endpoint to get bearer token"
  type        = string
}

variable "api_credentials_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing API credentials"
  type        = string
  default     = "api-cron-app-credentials"
}

variable "splunk_credentials_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing Splunk credentials"
  type        = string
  default     = "api-cron-splunk-credentials"
}

variable "additional_query_params" {
  description = "A JSON string of additional static query parameters to add to the API call."
  type        = string
  default     = "{}"
}

variable "create_api_secret" {
  description = "Whether to create the API credentials secret in Secrets Manager"
  type        = bool
  default     = true
}

variable "create_splunk_secret" {
  description = "Whether to create the Splunk credentials secret in Secrets Manager"
  type        = bool
  default     = true
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "api-cron-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name        = "api-cron-lambda-policy"
  description = "IAM policy for API cron Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          local.api_credentials_secret_arn,
          local.splunk_credentials_secret_arn
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Data sources to read existing secrets (if create_*_secret is false)
data "aws_secretsmanager_secret" "existing_api_credentials" {
  count = var.create_api_secret ? 0 : 1
  name  = var.api_credentials_secret_name
}

data "aws_secretsmanager_secret" "existing_splunk_credentials" {
  count = var.create_splunk_secret ? 0 : 1
  name  = var.splunk_credentials_secret_name
}

# Create new API credentials secret only if create_api_secret is true
resource "aws_secretsmanager_secret" "api_credentials" {
  count       = var.create_api_secret ? 1 : 0
  name        = var.api_credentials_secret_name
  description = "API authentication credentials for cron job"
  
  tags = {
    Purpose = "API Cron Job - Authentication"
    Environment = "production"
    SecretType = "api-credentials"
  }
}

# Create new Splunk credentials secret only if create_splunk_secret is true
resource "aws_secretsmanager_secret" "splunk_credentials" {
  count       = var.create_splunk_secret ? 1 : 0
  name        = var.splunk_credentials_secret_name
  description = "Splunk HEC credentials for cron job"
  
  tags = {
    Purpose = "API Cron Job - Splunk"
    Environment = "production"
    SecretType = "splunk-credentials"
  }
}

# Use the appropriate secret ARNs based on whether we created them or they exist
locals {
  api_credentials_secret_arn = var.create_api_secret ? aws_secretsmanager_secret.api_credentials[0].arn : data.aws_secretsmanager_secret.existing_api_credentials[0].arn
  splunk_credentials_secret_arn = var.create_splunk_secret ? aws_secretsmanager_secret.splunk_credentials[0].arn : data.aws_secretsmanager_secret.existing_splunk_credentials[0].arn
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_cron_logs" {
  name              = "/aws/lambda/api-cron-function"
  retention_in_days = 14
}

# Lambda function
resource "aws_lambda_function" "api_cron_function" {
  filename         = "api_cron_function.zip"
  function_name    = "api-cron-function"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      AUTH_ENDPOINT              = var.auth_endpoint
      API_ENDPOINT               = var.api_endpoint
      API_CREDENTIALS_SECRET_ARN = local.api_credentials_secret_arn
      SPLUNK_CREDENTIALS_SECRET_ARN = local.splunk_credentials_secret_arn
      ADDITIONAL_QUERY_PARAMS       = var.additional_query_params
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_cloudwatch_log_group.api_cron_logs,
    data.archive_file.lambda_zip
  ]
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "api_cron_function.zip"
  source {
    content = file("${path.module}/lambda_function.py")
    filename = "index.py"
  }
}

# EventBridge rule for scheduling
resource "aws_cloudwatch_event_rule" "api_cron_schedule" {
  name                = "api-cron-schedule"
  description         = "Trigger API cron job"
  schedule_expression = var.cron_schedule
}

# EventBridge target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.api_cron_schedule.name
  target_id = "ApiCronLambdaTarget"
  arn       = aws_lambda_function.api_cron_function.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_cron_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.api_cron_schedule.arn
}

# Outputs
output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.api_cron_function.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.api_cron_logs.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.api_cron_schedule.arn
}

output "api_credentials_secret_arn" {
  description = "ARN of the API credentials secret"
  value       = local.api_credentials_secret_arn
}

output "splunk_credentials_secret_arn" {
  description = "ARN of the Splunk credentials secret"
  value       = local.splunk_credentials_secret_arn
}
