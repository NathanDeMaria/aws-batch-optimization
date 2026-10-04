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

data "aws_subnets" "subnet_ids" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_batch_compute_environment" "compute" {
  name_prefix = "environment"

  compute_resources {
    instance_role = module.instance_role.arn

    # Three generations of the general-purpose family, both architectures,
    # three sizes each: 24 instance types, so 72 spot pools across the three
    # availability zones where the old list had 9. Pool count is the whole
    # input to the allocation strategy below -- a strategy cannot route around
    # a shortage it has nowhere to route to -- and churn is the real cost here:
    # cassandra's 2026-09-28 run had 26 reclaimed attempts across 49 children,
    # one of them nine times in a row.
    #
    # Deliberately all `m`, no `c` and no `r`. The jobs on this queue reserve
    # one vCPU and 2 GiB (see cassandra's optimize definition), so 4 GiB per
    # vCPU is the shape that packs exactly: every vCPU bought can hold a job.
    # A compute instance has 2 GiB per vCPU, which after the ECS agent's
    # overhead holds one job per *two* vCPUs -- so a c7i.large at $0.021 runs
    # one job where an m8a.large at $0.020 runs two, and an allocation strategy
    # optimising for instance price would happily pick the worse one. `r` has
    # the opposite problem: 8 GiB per vCPU is memory nothing here asks for, at
    # a price that reflects it.
    #
    # Measured per job-hour in us-east-2 on 2026-10-04, which is the number
    # that matters rather than the hourly rate: m7g.2xlarge $0.0096,
    # m8a.large $0.0097, m8g.2xlarge $0.0102, m8i.large and m6i.xlarge
    # $0.0111, against the $0.0300 a 2-vCPU job on an m6a.large used to cost.
    # Graviton wins at 2xlarge and loses badly at large (m8g.large is a thin
    # pool at $0.0398-0.0610) -- which is an argument for listing both and
    # letting the strategy choose, not for picking an architecture here.
    #
    # Capped at 2xlarge rather than naming bare families. A family name lets
    # Batch launch anything in it, and with `max_vcpus` at 16 that could be a
    # single 16-vCPU instance holding sixteen searches, all of which a single
    # reclaim would take out at once. Eight is enough blast radius.
    instance_type = [
      # Graviton. The image is a manifest list covering both architectures as
      # of cassandra's 2026-10-04 build; before that this fleet could only be
      # x86, because the image could only be x86.
      "m7g.large", "m7g.xlarge", "m7g.2xlarge",
      "m8g.large", "m8g.xlarge", "m8g.2xlarge",

      "m6i.large", "m6i.xlarge", "m6i.2xlarge",
      "m6a.large", "m6a.xlarge", "m6a.2xlarge",
      "m7i.large", "m7i.xlarge", "m7i.2xlarge",
      "m7a.large", "m7a.xlarge", "m7a.2xlarge",
      "m8i.large", "m8i.xlarge", "m8i.2xlarge",
      "m8a.large", "m8a.xlarge", "m8a.2xlarge",
    ]

    # No `image_id`. It was a hand-pasted x86 AMI id, which is not merely
    # stale -- it is what would stop every Graviton instance above from ever
    # launching, since Batch would hand a Graviton host an x86-64 AMI. There
    # is no arm64 image *type* to pair it with either: for ECS the types are
    # ECS_AL2, ECS_AL2_NVIDIA, ECS_AL2023 and ECS_AL2023_NVIDIA, and
    # ECS_AL2023 resolves to whichever architecture the instance it is
    # launching happens to be. Stated rather than left to the default so the
    # choice is visible, and `image_id` is deprecated in the Batch API in
    # favour of exactly this block.
    ec2_configuration {
      image_type = "ECS_AL2023"
    }

    max_vcpus = 16
    min_vcpus = 0

    security_group_ids = [
      var.security_group_id,
    ]
    subnets = data.aws_subnets.subnet_ids.ids

    type = "SPOT"

    # Unset until now, which meant BEST_FIT: pick the cheapest instance type
    # that fits and launch only that, with no regard for how likely that pool
    # is to be reclaimed. It is the default and it is the wrong one for work
    # measured in hours -- AWS's own guidance is this strategy, which weighs
    # price against the capacity signal EC2 publishes per pool.
    #
    # Worth more here than any instance-type edit: a reclaim costs the probes
    # since the last checkpoint plus a fresh `read_league`, and the run above
    # spent 79 instance-hours on 49 searches whose final attempts account for
    # 34 of them.
    #
    # Note that BEST_FIT is the one strategy Batch cannot update *into* or out
    # of in place, so expect this to replace the compute environment rather
    # than modify it; `name_prefix` and the `create_before_destroy` below are
    # already here for that. Anything running at the time dies with the old
    # environment, so apply it outside cassandra's 03:00 Monday and 09:00
    # daily windows.
    allocation_strategy = "SPOT_PRICE_CAPACITY_OPTIMIZED"

    # Only required for BEST_FIT, which this no longer is -- the other
    # strategies go through EC2 Fleet rather than Spot Fleet. Kept because it
    # is accepted and harmless, and because deleting the role is a separate
    # change from deciding not to need it.
    spot_iam_fleet_role = module.spot_fleet_role.arn

    bid_percentage = 100
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
