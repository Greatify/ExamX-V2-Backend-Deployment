# Terraform Outputs

output "environment" {
  description = "Current environment"
  value       = var.environment
}

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    environment      = var.environment
    region          = var.aws_region
    lambda_count    = length(local.lambdas)
    lambda_names    = [for k in keys(local.lambdas) : "${local.prefix}-lambda-${k}"]
    sqs_queues      = [for k, v in local.lambdas : "${local.prefix}-${v.queue}"]
    ecr_repositories = [for k in keys(local.lambdas) : "${local.prefix}-lambda-${k}"]
  }
}
