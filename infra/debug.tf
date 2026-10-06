# A role for looking into jobs by hand -- or by a Claude session -- across
# every app on the queue: read jobs, their logs, schedules, images and the
# data, and submit, cancel or terminate jobs. Nothing that changes
# infrastructure, and no PassRole, so a submitted job runs with whatever roles
# its job definition already names.
#
# Assumed from one IAM user whose only permission is the assume. Its access key
# is made by hand in the console, not here, so the secret never lands in
# terraform state.
# Anyone else who should debug is added to the role's trust, not given a key.

locals {
  debug_name         = "${var.resource_name_prefix}-debug"
  account_arn_suffix = "${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}"
  partition          = data.aws_partition.current.partition
}

data "aws_region" "current" {}

resource "aws_iam_user" "debug" {
  name = local.debug_name
  path = "/system/"

  tags = {
    Description = "Assumes ${local.debug_name} and holds nothing else"
  }

  # Its ARN only comes into the apply role's reach with the ci_apply_iam
  # change that ships alongside it, so that has to land first.
  depends_on = [aws_iam_policy.ci_apply_iam]
}

data "aws_iam_policy_document" "debug_user" {
  statement {
    sid       = "AssumeDebugRole"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.debug.arn]
  }
}

resource "aws_iam_policy" "debug_user" {
  name        = "${local.debug_name}-assume"
  description = "Assume ${local.debug_name}, and nothing else"
  policy      = data.aws_iam_policy_document.debug_user.json
}

resource "aws_iam_user_policy_attachment" "debug_user" {
  user       = aws_iam_user.debug.name
  policy_arn = aws_iam_policy.debug_user.arn
}

data "aws_iam_policy_document" "debug_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.debug.arn]
    }
  }
}

resource "aws_iam_role" "debug" {
  name               = local.debug_name
  description        = "Read and submit Batch jobs on ${aws_batch_job_queue.queue.name}, read their logs and data"
  assume_role_policy = data.aws_iam_policy_document.debug_assume.json
}

data "aws_iam_policy_document" "debug" {
  # Batch's Describe and List calls take no resource.
  statement {
    sid = "ReadBatch"
    actions = [
      "batch:DescribeComputeEnvironments",
      "batch:DescribeJobDefinitions",
      "batch:DescribeJobQueues",
      "batch:DescribeJobs",
      "batch:ListJobs",
      "batch:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # SubmitJob is authorized against the definition and the queue together, so
  # any app's definition, but only onto the shared queue.
  statement {
    sid     = "SubmitToTheQueue"
    actions = ["batch:SubmitJob"]
    resources = [
      "arn:${local.partition}:batch:${local.account_arn_suffix}:job-definition/*",
      aws_batch_job_queue.queue.arn,
    ]
  }

  # A bad backfill has to be stoppable by whoever started it.
  statement {
    sid = "StopJobs"
    actions = [
      "batch:CancelJob",
      "batch:TerminateJob",
    ]
    resources = ["arn:${local.partition}:batch:${local.account_arn_suffix}:job/*"]
  }

  # No job definition sets a log configuration, so every job logs to Batch's
  # default group.
  statement {
    sid = "ReadJobLogs"
    actions = [
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:StartQuery",
    ]
    resources = [
      "arn:${local.partition}:logs:${local.account_arn_suffix}:log-group:/aws/batch/job",
      "arn:${local.partition}:logs:${local.account_arn_suffix}:log-group:/aws/batch/job:*",
    ]
  }

  statement {
    sid = "ReadLogQueries"
    actions = [
      "logs:DescribeLogGroups",
      "logs:GetQueryResults",
      "logs:StopQuery",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ReadSchedules"
    actions = [
      "scheduler:GetSchedule",
      "scheduler:ListScheduleGroups",
      "scheduler:ListSchedules",
    ]
    resources = ["*"]
  }

  # Which image a tag points at, when a job ran something unexpected.
  statement {
    sid = "ReadImages"
    actions = [
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]
    resources = ["arn:${local.partition}:ecr:${local.account_arn_suffix}:repository/*"]
  }

  # What the jobs read and wrote. Read only: a job is how data changes.
  statement {
    sid       = "ListData"
    actions   = ["s3:ListBucket"]
    resources = module.buckets.arns
  }

  statement {
    sid       = "ReadData"
    actions   = ["s3:GetObject"]
    resources = [for arn in module.buckets.arns : "${arn}/*"]
  }

  # The queue, bucket and repo names every consumer's tooling finds things by
  # (ssm.tf). Nothing in it is secret, and without it a debug session has to
  # ask someone for the queue name before it can look at anything.
  statement {
    sid       = "ReadSharedOutputs"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.shared_outputs.arn]
  }
}

resource "aws_iam_policy" "debug" {
  name        = local.debug_name
  description = "Read and submit Batch jobs, read their logs, schedules, images and data"
  policy      = data.aws_iam_policy_document.debug.json
}

resource "aws_iam_role_policy_attachment" "debug" {
  role       = aws_iam_role.debug.name
  policy_arn = aws_iam_policy.debug.arn
}
