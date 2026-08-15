terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# A Batch job definition, with no opinion about what schedules it or what
# depends on it. Those are separate concerns: `job_schedule` handles the first,
# and the second can't live here at all -- Batch takes `dependsOn` on
# SubmitJob, not on the definition -- so DAG edges belong to whatever submits
# the run.
resource "aws_batch_job_definition" "this" {
  name = var.job_name
  type = "container"

  container_properties = jsonencode({
    image = var.image

    resourceRequirements = [
      {
        type  = "VCPU"
        value = tostring(var.vcpu)
      },
      {
        type  = "MEMORY"
        value = tostring(var.memory)
      }
    ]

    command     = var.command
    environment = var.environment_variables

    # Execution role: pulling the image from ECR. Job role: what the code
    # itself is allowed to touch.
    executionRoleArn = var.execution_role_arn
    jobRoleArn       = var.job_role_arn
  })

  platform_capabilities = ["EC2"]

  # Spot instances get reclaimed, and a reclaim looks nothing like a bug in the
  # job. Retrying only on host failure means an interrupted run restarts while
  # a genuinely failing one still fails on the first attempt, instead of
  # burning `attempts` copies of the same error.
  dynamic "retry_strategy" {
    for_each = var.retry_attempts > 1 ? [1] : []
    content {
      attempts = var.retry_attempts

      evaluate_on_exit {
        action           = "RETRY"
        on_status_reason = "Host EC2*"
      }

      evaluate_on_exit {
        action    = "EXIT"
        on_reason = "*"
      }
    }
  }

  # A job with no timeout that hangs holds a compute slot until someone
  # notices. Batch's own default is no timeout at all.
  dynamic "timeout" {
    for_each = var.timeout_seconds == null ? [] : [1]
    content {
      attempt_duration_seconds = var.timeout_seconds
    }
  }
}
