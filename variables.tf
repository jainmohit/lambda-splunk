# General Variables
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "cron_schedule" {
  description = "Cron schedule expression for the EventBridge rule"
  type        = string
  default     = "rate(5 minutes)" # Default to run every 5 minutes
}

# API and Authentication Variables
variable "auth_endpoint" {
  description = "Authentication endpoint to get the bearer token"
  type        = string
}

variable "api_endpoint" {
  description = "The main API endpoint to call after authentication"
  type        = string
}

variable "additional_query_params" {
  description = "A JSON string of additional static query parameters to add to the API call."
  type        = string
  default     = "{}"
}

# AWS Secrets Manager Variables
variable "api_credentials_secret_arn" {
  description = "The full ARN of the existing AWS Secrets Manager secret containing API credentials."
  type        = string
}

# CloudWatch Logging Variables
variable "log_group_name" {
  description = "Name of the CloudWatch Log Group for the Lambda function"
  type        = string
  default     = "/aws/lambda/api-cron-function"
}
