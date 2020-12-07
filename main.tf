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

module "instance_role" {
  source = "./instance_role"
}

module "network" {
  source = "./network"
}

module "compute_env" {
  source = "./compute_env"

  instance_role_arn = module.instance_role.arn
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
