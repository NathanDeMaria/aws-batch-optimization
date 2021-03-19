data "aws_caller_identity" "current" {}

resource "aws_iam_role" "aws_batch_service_role" {
  name = "aws_batch_service_role"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
    {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
        "Service": "batch.amazonaws.com"
        }
    }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "aws_batch_service_role" {
  role       = aws_iam_role.aws_batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

module "instance_role" {
  source = "./instance_role"
}

module "spot_fleet_role" {
  source = "./spot_fleet_role"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "subnet_ids" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_batch_compute_environment" "compute" {
  compute_environment_name_prefix = "environment"

  compute_resources {
    instance_role = module.instance_role.arn

    instance_type = [
      "c4.large",
    ]
    # latest Amazon ECS-optimized Amazon Linux 2 AMI (amzn2-ami-ecs-hvm-2.0.20210301-x86_64-ebs)
    image_id = "ami-02ef98ccecbf47e86"

    max_vcpus = 16
    min_vcpus = 0

    security_group_ids = [
      var.security_group_id,
    ]
    subnets = data.aws_subnet_ids.subnet_ids.ids

    type                = "SPOT"
    spot_iam_fleet_role = module.spot_fleet_role.arn
    bid_percentage      = 100
  }

  service_role = aws_iam_role.aws_batch_service_role.arn
  type         = "MANAGED"

  # Ugh...b/c of this issue, have to change the name each time this gets destroy/created
  # https://github.com/terraform-providers/terraform-provider-aws/issues/2044
  lifecycle {
    create_before_destroy = true
  }

  # If you don't depends_on this, the compute environment can enter an "INVALID"
  # state because it won't have permissions it thinks it needs,
  # so any API calls to edit (or delete) it will fail.
  # This makes sure that the compute env is deleted before the attachment, 
  # which doesn't happen by default because the only resource referenced
  # directly on this resource is the role, not the attachment
  depends_on = [
    aws_iam_role_policy_attachment.aws_batch_service_role
  ]
}
