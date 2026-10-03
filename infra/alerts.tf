# Failure email for every app on the queue. A job failing is a property of the
# queue, so it is alerted on here, once: endgame, cassandra and gold-rush
# declare no Batch failure rule of their own, and an app added to the queue is
# covered without doing anything.
#
# The topic is published in /batch/shared-outputs (ssm.tf) as
# `failure_topic_arn`, for failures that aren't a Batch job failing -- endgame
# routes its Step Functions chains' failures here, say. What deserves an alert
# beyond a failed job is each app's call; where the email goes is this one's.

locals {
  # An unset GitHub Actions secret interpolates to "", not to nothing, so CI
  # hands terraform `TF_VAR_notification_email=""`. Treat that as unset.
  notification_email = var.notification_email == "" ? null : var.notification_email
}

resource "aws_sns_topic" "failures" {
  name = "${var.resource_name_prefix}-failures"
}

# The subscription waits on a confirmation link AWS emails to the address; until
# someone clicks it, nothing is delivered.
resource "aws_sns_topic_subscription" "failures_email" {
  count     = local.notification_email == null ? 0 : 1
  topic_arn = aws_sns_topic.failures.arn
  protocol  = "email"
  endpoint  = local.notification_email
}

# Any EventBridge rule in this account may publish: the queue rule below, and
# the rules the app stacks point here.
data "aws_iam_policy_document" "failures_publish" {
  statement {
    sid       = "AllowEventsToPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.failures.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "failures" {
  arn    = aws_sns_topic.failures.arn
  policy = data.aws_iam_policy_document.failures_publish.json
}

resource "aws_cloudwatch_event_rule" "job_failed" {
  name        = "${var.resource_name_prefix}-job-failed"
  description = "Any job on ${aws_batch_job_queue.queue.name} entering FAILED"

  event_pattern = jsonencode({
    source      = ["aws.batch"]
    detail-type = ["Batch Job State Change"]
    detail = {
      status   = ["FAILED"]
      jobQueue = [aws_batch_job_queue.queue.arn]
      # Array children each report FAILED; a 20-child array failing would be
      # 20 emails. The parent's one says the same thing. A job that isn't an
      # array has no arrayProperties at all, so it still matches.
      arrayProperties = {
        index = [{ exists = false }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "job_failed" {
  rule      = aws_cloudwatch_event_rule.job_failed.name
  target_id = "sns"
  arn       = aws_sns_topic.failures.arn

  input_transformer {
    input_paths = {
      jobName = "$.detail.jobName"
      status  = "$.detail.status"
      reason  = "$.detail.statusReason"
      jobId   = "$.detail.jobId"
    }
    input_template = "\"Job <jobName> (ID: <jobId>) has <status>. Reason: <reason>\""
  }
}
