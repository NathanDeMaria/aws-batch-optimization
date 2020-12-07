terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.20.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-2"
}

module "network" {
  source = "./network"
}

module "compute_env" {
  source = "./compute_env"

  security_group_id = module.network.security_group_id
  subnet_id         = module.network.subnet_id
}

resource "aws_batch_job_queue" "test_queue" {
  name     = "job-queue"
  state    = "ENABLED"
  priority = 1
  compute_environments = [
    module.compute_env.arn,
  ]
}
