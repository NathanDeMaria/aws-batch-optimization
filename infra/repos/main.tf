locals {
  # Every app image the queue runs. None of them has a push user: each repo's
  # CI pushes by OIDC, with an image role its own `jobs/` stack owns
  # (`<repo>/jobs/oidc.tf`), scoped to its one repository here.
  repositories = ["endgame", "cassandra", "gold-rush"]
}

resource "aws_ecr_repository" "repos" {
  for_each = toset(local.repositories)

  name                 = each.key
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Nothing deleted an image until this existed, and every build leaves three:
# the one it tagged, the layer-cache manifest it replaced, and whatever the
# previous build's cache pointed at. Measured 2026-10-04, across the three
# repositories: 469 GB of nominal image size over 844 images, 520 of them
# untagged, against an ECR bill of $4.75/month -- most of that nominal size is
# shared layers, so the cost is modest, but it only goes one direction.
#
# Two rules, and the order they're written in is not the order that matters --
# ECR evaluates every rule against every image, so a rule cannot protect
# anything. What protects a tag is not being matched:
#
#   untagged, after a week. This is the rule that reclaims the space, and the
#   one worth being careful about, because a multi-architecture image is an
#   index whose per-architecture manifests carry no tags of their own. ECR
#   does not expire a manifest that a tagged index refers to -- checked with
#   `start-lifecycle-policy-preview` against cassandra, where 106 untagged
#   index children older than the window were offered to the rule and none
#   was selected -- so this is safe for the manifest lists CI now pushes. A
#   week rather than a day so there is time to notice a mistake.
#
#   `sha-` tags, after three months. CI prefixes every build tag (see
#   cassandra's image workflow), which is what makes this expressible at all:
#   `tagPrefixList` holds at most 10 entries, so "every 7-character hex tag"
#   -- 16 prefixes -- does not fit, and `tagPatternList` has no way to say
#   "except latest". The namespace also means a tag added by hand is kept
#   indefinitely, which is the right default for one a person chose.
#
# `latest` and the `buildcache-*` refs match neither rule and are never
# expired. The cache manifests they displace are untagged, which is how the
# space actually comes back.
#
# Repository-by-repository rather than one shared policy document only because
# `aws_ecr_lifecycle_policy` is per repository; the text is the same for all
# three. An app that doesn't use `sha-` tags simply never matches the second
# rule.
resource "aws_ecr_lifecycle_policy" "repos" {
  for_each = aws_ecr_repository.repos

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after a week"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire build tags after three months"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "sinceImagePushed"
          countUnit     = "days"
          countNumber   = 90
        }
        action = { type = "expire" }
      },
    ]
  })
}
