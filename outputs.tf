output "lambda_function_arn" {
  description = "ARN of the created Lambda function"
  value       = aws_lambda_function.api_cron_function.arn
}

output "cloudwatch_log_group" {
  description = "Name of the CloudWatch log group for the Lambda function"
  value       = aws_cloudwatch_log_group.api_cron_logs.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge scheduling rule"
  value       = aws_cloudwatch_event_rule.api_cron_schedule.arn
}

output "api_credentials_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret for API credentials"
  value       = local.api_credentials_secret_arn
}
