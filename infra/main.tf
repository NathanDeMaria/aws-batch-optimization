terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.44"
    }
  }

  backend "s3" {
    bucket  = "nathan-terraform"
    encrypt = true
    key     = "batch-state"
    region  = "us-east-2"

    # S3-native locking, so there's no DynamoDB table to provision. Matters
    # now that CI applies: two overlapping runs would otherwise write the same
    # state with nothing stopping them.
    use_lockfile = true
  }
}

provider "aws" {
  # Deliberately not `profile = "default"`. GitHub Actions gets credentials
  # from OIDC as environment variables, and naming a profile makes the
  # provider look for ~/.aws/credentials instead and fail with "no valid
  # credential sources". Leaving it unset costs nothing locally: with no
  # profile named, the SDK reads the `default` profile anyway.
  region = "us-east-2"
}

module "buckets" {
  source = "./buckets"
  prefix = "nathan"
}

module "job_role" {
  source      = "./job_role"
  bucket_arns = module.buckets.arns
}

module "network" {
  source = "./network"
}

module "compute_env" {
  source = "./compute_env"

  security_group_id = module.network.security_group_id
}

resource "aws_batch_job_queue" "queue" {
  name     = "job-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = module.compute_env.arn
  }
}

module "repos" {
  source = "./repos"
}

# Roles every job needs, regardless of which repo deploys it. Apps still bring
# their own job role -- that's the one that varies with what the code touches.
module "batch_roles" {
  source = "./batch_roles"

  job_queue_arn = aws_batch_job_queue.queue.arn
}
