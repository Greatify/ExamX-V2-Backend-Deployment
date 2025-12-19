# Lambda Functions - Using single ECR with tagged images

resource "aws_lambda_function" "lambdas" {
  for_each = local.lambdas
  
  function_name = "${local.prefix}-lambda-${each.key}"
  role          = aws_iam_role.lambda_execution.arn
  package_type  = "Image"
  
  # Single ECR repo with image tag: {lambda-name}-{environment}
  image_uri = "${aws_ecr_repository.lambda.repository_url}:${each.key}-${var.environment}"
  
  timeout     = each.value.timeout
  memory_size = each.value.memory_size
  
  description = each.value.description
  
  environment {
    variables = {
      LAMBDA_ENV     = var.environment
      AWS_REGION     = var.aws_region
      AWS_ACCOUNT_ID = var.aws_account_id
      SECRETS_ARN    = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:examxv2-secrets-1uLP4S"
    }
  }
  
  tags = {
    Name        = "${local.prefix}-lambda-${each.key}"
    Lambda      = each.key
    Environment = var.environment
  }
  
  depends_on = [
    aws_iam_role_policy.lambda_custom,
    aws_ecr_repository.lambda
  ]
}

# SQS Event Source Mapping
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  for_each = local.lambdas
  
  event_source_arn = aws_sqs_queue.lambda_queues[each.key].arn
  function_name    = aws_lambda_function.lambdas[each.key].arn
  
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  
  function_response_types = ["ReportBatchItemFailures"]
  
  scaling_config {
    maximum_concurrency = 100
  }
  
  depends_on = [
    aws_lambda_function.lambdas
  ]
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = local.lambdas
  
  name              = "/aws/lambda/${local.prefix}-lambda-${each.key}"
  retention_in_days = 30
  
  tags = {
    Name   = "${local.prefix}-lambda-${each.key}-logs"
    Lambda = each.key
  }
}

# CloudWatch Alarms for Lambda Errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambdas
  
  alarm_name          = "${local.prefix}-lambda-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Lambda ${each.key} error rate exceeded"
  
  dimensions = {
    FunctionName = aws_lambda_function.lambdas[each.key].function_name
  }
  
  tags = {
    Name   = "${local.prefix}-lambda-${each.key}-error-alarm"
    Lambda = each.key
  }
}

output "lambda_arns" {
  description = "Lambda function ARNs"
  value       = { for k, v in aws_lambda_function.lambdas : k => v.arn }
}

output "lambda_function_names" {
  description = "Lambda function names"
  value       = { for k, v in aws_lambda_function.lambdas : k => v.function_name }
}

output "lambda_image_tags" {
  description = "Lambda image tags"
  value       = { for k in keys(local.lambdas) : k => "${k}-${var.environment}" }
}
