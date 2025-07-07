# EventBridge rule for scheduling the Lambda function
resource "aws_cloudwatch_event_rule" "api_cron_schedule" {
  name                = "api-cron-schedule"
  description         = "Trigger the API cron job Lambda function"
  schedule_expression = var.cron_schedule
}

# EventBridge target to invoke the Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.api_cron_schedule.name
  target_id = "ApiCronLambdaTarget"
  arn       = aws_lambda_function.api_cron_function.arn
}

# Lambda permission to allow invocation from EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_cron_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.api_cron_schedule.arn
}
