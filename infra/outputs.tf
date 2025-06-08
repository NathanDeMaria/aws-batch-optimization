output "bucket" {
  value = module.buckets.bucket_name
}

output "temp_bucket" {
  value = module.buckets.temp_bucket_name
}

output "job_queue_name" {
  value = aws_batch_job_queue.queue.name
}

output "job_role_arn" {
  value = module.job_role.arn
}

output "repo_urls" {
  value = module.repos.named_urls
}

output "ecr_iam_users" {
  value     = module.repos.ecr_iam_users
  sensitive = true
}
