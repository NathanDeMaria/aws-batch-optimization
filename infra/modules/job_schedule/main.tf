terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# An EventBridge schedule that submits one Batch job. Separate from
# `batch_job` so a definition can carry several schedules with different
# command overrides -- which is how a single launcher definition serves both a
# weekly full run and a daily publish-only one -- and so a definition that is
# only ever submitted by a launcher carries no schedule at all.
resource "aws_scheduler_schedule" "this" {
  name       = var.schedule_name
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:batch:submitJob"
    role_arn = var.scheduler_role_arn

    # The universal-target input is the SubmitJob request body, so anything
    # SubmitJob accepts can go here -- including ContainerOverrides. What it
    # cannot express is DependsOn, which needs job IDs that don't exist until
    # something has already submitted: that is why multi-stage runs go through
    # a launcher job rather than a schedule per stage.
    input = jsonencode(merge(
      {
        JobName       = var.schedule_name
        JobQueue      = var.job_queue_arn
        JobDefinition = var.job_definition
      },
      length(var.command) == 0 ? {} : {
        ContainerOverrides = {
          Command = var.command
        }
      },
      var.array_size == null ? {} : {
        ArrayProperties = {
          Size = var.array_size
        }
      },
    ))
  }
}
