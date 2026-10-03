# GitHub Actions authenticates by OIDC rather than a long-lived access key.
# Two roles, not one: `terraform plan` executes provider code and runs on every
# branch and PR, so it must not be able to reach credentials that can apply.
#
# Mirrors the setup in NathanDeMaria/invisible-string.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  owner = split("/", var.github_repository)[0]
  name  = split("/", var.github_repository)[1]

  # The ID-qualified subject GitHub actually issues. IDs rather than names is
  # the point of the format: a repository can be renamed, but its ID can't be
  # taken over by someone else claiming the old name.
  subject_repo = "repo:${local.owner}@${var.github_owner_id}/${local.name}@${var.github_repository_id}"

  # Kept alongside it so the policy still works if an account is ever issuing
  # the older name-only subjects. Both forms are exact, so listing both widens
  # nothing -- GitHub signs the claim, it can't be spoofed.
  subject_repo_legacy = "repo:${var.github_repository}"

  # `one(...[*].arn)` rather than invisible-string's `var.x ? ...[0].arn : ...`
  # ternary. The two are equivalent when the provider is being created, which
  # is that stack's default -- but this one defaults to *not* creating it, and
  # indexing `[0]` into a count=0 resource is exactly the case where the
  # ternary can fail on "Invalid index" instead of taking the other branch.
  # `one` returns null for an empty list, which coalesce then skips.
  oidc_provider_arn = coalesce(
    one(aws_iam_openid_connect_provider.github[*].arn),
    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com",
  )

  iam_prefix = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}"

  # The IAM this stack manages, for scoping the apply role.
  #
  # invisible-string scopes to a single `${prefix}-*`, which doesn't work here:
  # this stack predates any naming convention and its roles are named
  # `job-role`, `ecs_instance_role`, `spot-fleet-role` and
  # `aws_batch_service_role`. Rather than widen to IAMFullAccess -- which would
  # let a compromised workflow mint itself an admin role -- the pre-convention
  # names are listed out and everything new goes under `batch-*`, so this list
  # stops growing.
  managed_role_arns = [
    "${local.iam_prefix}:role/${var.resource_name_prefix}-*",
    "${local.iam_prefix}:role/job-role",
    "${local.iam_prefix}:role/aws_batch_service_role",
    "${local.iam_prefix}:role/ecs_instance_role",
    "${local.iam_prefix}:role/spot-fleet-role",
  ]

  managed_policy_arns = [
    "${local.iam_prefix}:policy/${var.resource_name_prefix}-*",
  ]

  # The path matters: users here live on `/system/`, and the ARN of a user
  # with a path includes it. `batch-*` there is debug.tf's user, whose key is
  # made by hand; the access-key actions below reach it too, but terraform
  # never calls them for it.
  managed_user_arns = [
    "${local.iam_prefix}:user/system/${var.resource_name_prefix}-*",
  ]

  managed_instance_profile_arns = [
    "${local.iam_prefix}:instance-profile/ecs_instance_role",
    "${local.iam_prefix}:instance-profile/${var.resource_name_prefix}-*",
  ]
}

# NB: the apply role can read this provider but not create or delete one --
# `ReadIam` below grants GetOpenIDConnectProvider and nothing more. Flipping
# `create_oidc_provider` to true therefore needs a local apply, not a CI one.
# That costs nothing today: the very first apply is local anyway, because it is
# what creates the CI roles.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []
}

# ------------------------------------------------------------------------------
# Trust policies
#
# The `sub` claim's shape depends on the event, which is the easy thing to get
# wrong: a branch push is `repo:owner/name:ref:refs/heads/<branch>`, but a pull
# request is `repo:owner/name:pull_request` with no ref at all. A plan role
# trusting only `ref:refs/heads/*` therefore fails on every PR.
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "plan_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.subject_repo}:ref:refs/heads/*",
        "${local.subject_repo}:pull_request",
        "${local.subject_repo_legacy}:ref:refs/heads/*",
        "${local.subject_repo_legacy}:pull_request",
      ]
    }
  }
}

data "aws_iam_policy_document" "apply_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringLike only because two exact alternatives are listed; neither
    # contains a wildcard, so "main-hotfix" still cannot match. Keeping the
    # branch segment literal is what stops any branch merely starting with
    # "main" from gaining apply rights.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.subject_repo}:ref:refs/heads/main",
        "${local.subject_repo_legacy}:ref:refs/heads/main",
      ]
    }
  }
}

# ------------------------------------------------------------------------------
# Plan role: read everything, write nothing except the state lock.
# ------------------------------------------------------------------------------

resource "aws_iam_role" "ci_plan" {
  name               = "${var.resource_name_prefix}-ci-plan"
  description        = "terraform plan from any branch or PR of ${var.github_repository}"
  assume_role_policy = data.aws_iam_policy_document.plan_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ci_plan_readonly" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

# Plan reads state and takes the lock, so it needs writes on the lock object
# even though it changes no infrastructure.
data "aws_iam_policy_document" "terraform_state" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket}"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    # Covers `batch-state` and the `batch-state.tflock` that S3-native
    # locking writes next to it.
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket}/${var.state_key_prefix}*",
    ]
  }
}

resource "aws_iam_policy" "terraform_state" {
  name        = "${var.resource_name_prefix}-terraform-state"
  description = "Read/write this stack's terraform state and its lock file"
  policy      = data.aws_iam_policy_document.terraform_state.json
}

resource "aws_iam_role_policy_attachment" "ci_plan_state" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = aws_iam_policy.terraform_state.arn
}

# ------------------------------------------------------------------------------
# Apply role: main only.
# ------------------------------------------------------------------------------

resource "aws_iam_role" "ci_apply" {
  name               = "${var.resource_name_prefix}-ci-apply"
  description        = "terraform apply from main of ${var.github_repository}"
  assume_role_policy = data.aws_iam_policy_document.apply_assume_role.json
}

# PowerUserAccess covers Batch, EC2, ECR, S3 and EventBridge, and explicitly
# denies IAM. The IAM this stack needs is added below, scoped by name, rather
# than by attaching IAMFullAccess. It does allow iam:CreateServiceLinkedRole,
# which Batch and Spot Fleet both need.
resource "aws_iam_role_policy_attachment" "ci_apply_poweruser" {
  role       = aws_iam_role.ci_apply.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "ci_apply_iam" {
  statement {
    sid    = "ManageOwnRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = local.managed_role_arns
  }

  statement {
    sid    = "ManageOwnPolicies"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:ListEntitiesForPolicy",
    ]
    # Reads deliberately absent: `ReadIam` below already allows GetPolicy and
    # GetPolicyVersion on `*`, which it has to -- terraform refreshes the
    # AWS-managed policies this stack attaches, and those aren't ours to list
    # here.
    resources = local.managed_policy_arns
  }

  # The `/system/` users this stack owns, and their access keys. Creating an
  # access key is the sharpest thing in this policy, so it is scoped to those:
  # `batch-debug`, which can only assume its role.
  statement {
    sid    = "ManageSystemUsers"
    effect = "Allow"
    actions = [
      "iam:CreateUser",
      "iam:DeleteUser",
      "iam:GetUser",
      # The provider lists a user's groups before deleting it, to remove it
      # from them, whether or not it is in any.
      "iam:ListGroupsForUser",
      "iam:TagUser",
      "iam:UntagUser",
      "iam:ListUserTags",
      "iam:AttachUserPolicy",
      "iam:DetachUserPolicy",
      "iam:ListAttachedUserPolicies",
      "iam:ListUserPolicies",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:UpdateAccessKey",
      "iam:ListAccessKeys",
      "iam:GetAccessKeyLastUsed",
    ]
    resources = local.managed_user_arns
  }

  # The batch compute environment launches instances with a profile, which is
  # a separate IAM resource type from the role inside it.
  statement {
    sid    = "ManageInstanceProfiles"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = local.managed_instance_profile_arns
  }

  # Batch, EC2 and the scheduler each need a role handed to them at create
  # time.
  statement {
    sid       = "PassOwnRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.managed_role_arns
  }

  # Reading is needed for plan-time refresh of things this stack references
  # but doesn't own -- and for the AWS-managed policies it attaches.
  statement {
    sid    = "ReadIam"
    effect = "Allow"
    actions = [
      "iam:ListRoles",
      "iam:ListPolicies",
      "iam:ListInstanceProfiles",
      "iam:ListInstanceProfilesForRole",
      "iam:GetOpenIDConnectProvider",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_apply_iam" {
  name        = "${var.resource_name_prefix}-ci-apply-iam"
  description = "IAM management scoped to the roles, policies and users this stack owns"
  policy      = data.aws_iam_policy_document.ci_apply_iam.json
}

resource "aws_iam_role_policy_attachment" "ci_apply_iam" {
  role       = aws_iam_role.ci_apply.name
  policy_arn = aws_iam_policy.ci_apply_iam.arn
}

resource "aws_iam_role_policy_attachment" "ci_apply_state" {
  role       = aws_iam_role.ci_apply.name
  policy_arn = aws_iam_policy.terraform_state.arn
}
