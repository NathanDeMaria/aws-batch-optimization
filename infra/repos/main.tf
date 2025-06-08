resource "aws_ecr_repository" "repos" {
  for_each = toset(["endgame"])

  name                 = each.key
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_user" "ecr_pusher" {
  for_each = aws_ecr_repository.repos
  name     = "ecr-pusher-${each.key}"
  path     = "/system/"

  tags = {
    Description = "IAM user to push images to the ${each.key} ECR repository"
  }
}

data "aws_iam_policy_document" "ecr_push_policy_document" {
  for_each = aws_ecr_repository.repos

  statement {
    sid = "AllowPushAndPullECR"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]
    resources = [
      each.value.arn # References the ARN of the current repository in the loop
    ]
  }

  statement {
    sid = "AllowECRLogin"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"] # GetAuthorizationToken must be allowed on all resources
  }
}

resource "aws_iam_policy" "ecr_push_policy" {
  for_each    = aws_ecr_repository.repos
  name        = "ecr-push-policy-${each.key}"
  path        = "/"
  description = "Policy to allow pushing and pulling images for the ${each.key} ECR repository"
  policy      = data.aws_iam_policy_document.ecr_push_policy_document[each.key].json
}

resource "aws_iam_user_policy_attachment" "ecr_pusher_attachment" {
  for_each   = aws_ecr_repository.repos
  user       = aws_iam_user.ecr_pusher[each.key].name
  policy_arn = aws_iam_policy.ecr_push_policy[each.key].arn
}

# Create access keys for ECR push users
resource "aws_iam_access_key" "ecr_access_key" {
  for_each = aws_iam_user.ecr_pusher
  user     = each.value.name
}
