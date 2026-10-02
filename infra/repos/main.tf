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
