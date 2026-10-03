# What the stacks built on this one (cassandra, gold-rush, EndGame) read from
# it: one JSON parameter holding the outputs below, keyed by output name.
#
# They used to read this stack's state file instead -- terraform through
# `terraform_remote_state`, CI image pushes with `aws s3 cp` -- which hard-coded
# the state's bucket and key into every consumer, and meant read access to the
# whole state was the only way to get a bucket name. The state holds every
# resource attribute, sensitive ones included. This parameter holds only what
# is listed here, and a role can be granted it by ARN alone.
#
# Same shape as `terraform_remote_state`'s `outputs`, so a consumer's
# `jsondecode(...)` drops in where that was. A plain String, not a
# SecureString: nothing in it is secret, and `insecure_value` then reads it
# without terraform marking every job definition that uses it as sensitive.
#
# Add an output here only if it is safe for any consumer's CI to read.

resource "aws_ssm_parameter" "shared_outputs" {
  name        = var.shared_outputs_parameter
  description = "Non-sensitive outputs of aws-batch-optimization, as JSON"
  type        = "String"

  value = jsonencode({
    bucket                   = module.buckets.bucket_name
    temp_bucket              = module.buckets.temp_bucket_name
    job_queue_name           = aws_batch_job_queue.queue.name
    job_queue_arn            = aws_batch_job_queue.queue.arn
    job_role_arn             = module.job_role.arn
    batch_execution_role_arn = module.batch_roles.execution_role_arn
    batch_scheduler_role_arn = module.batch_roles.scheduler_role_arn
    repo_urls                = module.repos.named_urls
    failure_topic_arn        = aws_sns_topic.failures.arn
  })
}
