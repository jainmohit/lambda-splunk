# CloudWatch Log Group for the Lambda function
resource "aws_cloudwatch_log_group" "api_cron_logs" {
  name              = "/aws/lambda/api-cron-function"
  retention_in_days = 14
}

# Create a zip archive of the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/api_cron_function.zip"
  source {
    content  = file("${path.module}/lambda_function.py")
    filename = "index.py"
  }
}

# Lambda function resource
resource "aws_lambda_function" "api_cron_function" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "api-cron-function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.9"
  timeout          = 60

  environment {
    variables = {
      AUTH_ENDPOINT                 = var.auth_endpoint
      API_ENDPOINT                  = var.api_endpoint
      API_CREDENTIALS_SECRET_ARN    = local.api_credentials_secret_arn
      ADDITIONAL_QUERY_PARAMS       = var.additional_query_params
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attachment,
    aws_cloudwatch_log_group.api_cron_logs,
  ]
}
