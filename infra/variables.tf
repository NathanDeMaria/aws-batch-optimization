variable "github_repository" {
  description = "owner/repo allowed to assume the CI roles"
  type        = string
  default     = "NathanDeMaria/aws-batch-optimization"
}

variable "github_owner_id" {
  description = <<-EOT
    Numeric ID of the GitHub account owning the repository.

    GitHub issues OIDC subjects in an immutable, ID-qualified form --
    `repo:OWNER@OWNER_ID/REPO@REPO_ID:...` -- rather than by name, so the trust
    policy has to match on IDs. Matching on names alone silently never matches
    and every assume fails with a generic "Not authorized".

      gh api users/NathanDeMaria --jq .id
  EOT
  type        = number
  default     = 5595197
}

variable "github_repository_id" {
  description = <<-EOT
    Numeric ID of the repository. See github_owner_id.

      gh api repos/NathanDeMaria/aws-batch-optimization --jq .id
  EOT
  type        = number
  default     = 350205237
}

variable "create_oidc_provider" {
  description = <<-EOT
    Create the GitHub Actions OIDC provider.

    Defaults false, unlike invisible-string, which creates it. IAM permits
    exactly one provider per URL per account, and invisible-string is in this
    same account -- so this stack expects to find that one rather than fail
    with EntityAlreadyExists. Set true if this account has no provider yet,
    and then set invisible-string's to false.
  EOT
  type        = bool
  default     = false
}

variable "state_bucket" {
  description = "Bucket holding terraform state. Plan needs write access for the lock file."
  type        = string
  default     = "nathan-terraform"
}

variable "state_key_prefix" {
  description = <<-EOT
    Key prefix within the state bucket that CI may lock and write.

    Not a directory: this stack's state is the object `batch-state`, and
    S3-native locking writes `batch-state.tflock` beside it, so the prefix
    covers both.
  EOT
  type        = string
  default     = "batch-state"
}

variable "resource_name_prefix" {
  description = <<-EOT
    Prefix for resources this stack creates from here on, and what scopes the
    apply role's IAM permissions.

    The pre-existing roles (`job-role`, `ecs_instance_role`, `spot-fleet-role`,
    `aws_batch_service_role`) predate this and are listed out individually in
    oidc.tf. New IAM should use this prefix so that list stops growing.
  EOT
  type        = string
  default     = "batch"
}
