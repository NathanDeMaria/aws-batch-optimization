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

# ------------------------------------------------------------------------------
# CI
# ------------------------------------------------------------------------------
# Set these as repository *variables* (not secrets -- a role ARN isn't one, and
# the workflow checks them against '' to stay dormant until they're wired up):
#   gh variable set AWS_PLAN_ROLE_ARN  --body "$(terraform output -raw ci_plan_role_arn)"
#   gh variable set AWS_APPLY_ROLE_ARN --body "$(terraform output -raw ci_apply_role_arn)"

output "ci_plan_role_arn" {
  description = "role-to-assume for plan jobs (any branch, any PR)"
  value       = aws_iam_role.ci_plan.arn
}

output "ci_apply_role_arn" {
  description = "role-to-assume for apply jobs (main only)"
  value       = aws_iam_role.ci_apply.arn
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC provider trusted by both roles"
  value       = local.oidc_provider_arn
}

# ------------------------------------------------------------------------------
# Debugging
# ------------------------------------------------------------------------------
# The user holds nothing but the assume; its access key is created by hand
# (IAM console, or `aws iam create-access-key --user-name ...`) so the secret
# stays out of state.

output "debug_role_arn" {
  description = "Read and submit jobs across the queue; assumed from debug_user_name"
  value       = aws_iam_role.debug.arn
}

output "debug_user_name" {
  value = aws_iam_user.debug.name
}
