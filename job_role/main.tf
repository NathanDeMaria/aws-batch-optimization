data "aws_iam_policy_document" "job_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "job_role" {
  name               = "job-role"
  assume_role_policy = data.aws_iam_policy_document.job_role_policy.json
}

resource "aws_iam_role_policy" "bucket_io" {
  name = "bucket-io"
  role = aws_iam_role.job_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action : [
          "s3:GetObject",
          "s3:PutObject",
        ],
        Effect : "Allow",
        Resource : [
          var.bucket_arn,
          "${var.bucket_arn}/*",
        ],
      }
    ]
  })
}
