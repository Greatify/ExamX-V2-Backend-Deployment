# SQS Queues for Lambda triggers

# Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  name                       = "${local.prefix}-dlq"
  message_retention_seconds  = 1209600  # 14 days
  receive_wait_time_seconds  = 20
  
  tags = {
    Name = "${local.prefix}-dlq"
    Type = "DLQ"
  }
}

# Lambda Task Queues
resource "aws_sqs_queue" "lambda_queues" {
  for_each = local.lambdas
  
  name                       = "${local.prefix}-${each.value.queue}"
  visibility_timeout_seconds = each.value.timeout * 6  # 6x Lambda timeout
  message_retention_seconds  = 1209600  # 14 days
  receive_wait_time_seconds  = 20       # Long polling
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = {
    Name   = "${local.prefix}-${each.value.queue}"
    Lambda = each.key
  }
}

# Results Queue
resource "aws_sqs_queue" "results" {
  name                       = "${local.prefix}-results"
  message_retention_seconds  = 86400  # 1 day
  receive_wait_time_seconds  = 20
  
  tags = {
    Name = "${local.prefix}-results"
    Type = "Results"
  }
}

# Heavy Tasks Queue (for Celery)
resource "aws_sqs_queue" "heavy_tasks" {
  name                       = "${local.prefix}-heavy-tasks"
  visibility_timeout_seconds = 3600  # 1 hour
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  
  tags = {
    Name = "${local.prefix}-heavy-tasks"
    Type = "Celery"
  }
}

output "sqs_queue_urls" {
  description = "SQS queue URLs"
  value = merge(
    { for k, v in aws_sqs_queue.lambda_queues : k => v.url },
    {
      dlq         = aws_sqs_queue.dlq.url
      results     = aws_sqs_queue.results.url
      heavy_tasks = aws_sqs_queue.heavy_tasks.url
    }
  )
}

output "sqs_queue_arns" {
  description = "SQS queue ARNs"
  value = merge(
    { for k, v in aws_sqs_queue.lambda_queues : k => v.arn },
    {
      dlq         = aws_sqs_queue.dlq.arn
      results     = aws_sqs_queue.results.arn
      heavy_tasks = aws_sqs_queue.heavy_tasks.arn
    }
  )
}
