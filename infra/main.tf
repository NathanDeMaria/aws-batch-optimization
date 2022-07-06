terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.20.0"
    }
  }

  backend "s3" {
    bucket         = "nathan-terraform"
    encrypt        = true
    key            = "batch-state"
    region         = "us-east-2"
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-2"
}

module "buckets" {
  source = "./buckets"
}

module "job_role" {
  source     = "./job_role"
  bucket_arn = module.buckets.temp_bucket_arn
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
  compute_environments = [
    module.compute_env.arn,
  ]
}
