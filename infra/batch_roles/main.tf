# The two roles that are the same for every job in the account, regardless of
# what the job does. Both are here rather than in an app's own terraform
# because neither has anything app-specific in it: the execution role pulls
# images and writes logs, and the scheduler role submits to the shared queue.
#
# The *job* role -- what the container's own code may touch -- deliberately
# stays with the app, since that's the one that varies. `job_role` next door is
# the shared-bucket default for jobs that need nothing else.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# Execution role: the Batch/ECS agent, not the application
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "batch-execution-role"
  assume_role_policy = data.aws_iam_policy_document.execution_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ------------------------------------------------------------------------------
# Scheduler role: what EventBridge Scheduler assumes to submit jobs
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "batch-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid     = "SubmitBatchJobs"
    actions = ["batch:SubmitJob"]
    resources = [
      var.job_queue_arn,
      # Job definitions come and go as apps deploy, and a schedule that names
      # one is already scoped by the queue above.
      "arn:aws:batch:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:job-definition/*",
    ]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "submit-jobs"
  role   = aws_iam_role.scheduler.name
  policy = data.aws_iam_policy_document.scheduler.json
}
