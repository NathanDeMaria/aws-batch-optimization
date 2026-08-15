output "bucket" {
  value = module.buckets.bucket_name
}

output "temp_bucket" {
  value = module.buckets.temp_bucket_name
}

output "job_queue_name" {
  value = aws_batch_job_queue.queue.name
}

# EventBridge Scheduler targets and Batch dependency wiring both want the ARN,
# not the name.
output "job_queue_arn" {
  value = aws_batch_job_queue.queue.arn
}

output "job_role_arn" {
  value = module.job_role.arn
}

output "batch_execution_role_arn" {
  value = module.batch_roles.execution_role_arn
}

output "batch_scheduler_role_arn" {
  value = module.batch_roles.scheduler_role_arn
}

output "repo_urls" {
  value = module.repos.named_urls
}

output "ecr_iam_users" {
  value     = module.repos.ecr_iam_users
  sensitive = true
}
