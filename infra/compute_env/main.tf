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

    # Three generations of the general-purpose family, three sizes each: 18
    # instance types, so 54 spot pools across the three availability zones
    # where the old list had 9. Pool count is the whole input to the allocation
    # strategy below -- a strategy cannot route around a shortage it has
    # nowhere to route to -- and churn is the real cost here: cassandra's
    # 2026-09-28 run had 26 reclaimed attempts across 49 children, one of them
    # nine times in a row.
    #
    # x86 only, and not by choice. Graviton was in this list for one apply,
    # which Batch rejected outright:
    #
    #   ClientException: arm-based instance type cannot be used with other
    #   instance types.
    #
    # A compute environment is single-architecture, full stop. Mixing the two
    # means two environments on one queue, and a queue tries its environments
    # in order rather than pricing across them -- so the second would be
    # overflow capacity for when the first hits `max_vcpus`, not a cheaper
    # alternative the strategy could pick. Measured below, the best Graviton
    # option beats the best x86 one by about 1%, which does not pay for a
    # second environment, a second `max_vcpus` to apportion, and an ordering
    # to reason about. Worth revisiting only if churn stays bad with 54 pools.
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
    # that matters rather than the hourly rate: m8a.large $0.0097, m8i.large
    # and m6i.xlarge $0.0111, m7i.xlarge and m6a.xlarge $0.0143-0.0147,
    # against the $0.0300 a 2-vCPU job on an m6a.large used to cost. The
    # Graviton options this cannot have were m7g.2xlarge $0.0096 and
    # m8g.2xlarge $0.0102 -- so m8a.large gives up 1% to the best of them,
    # and m8g.large would have been the worst instance on the list either
    # way (a thin pool at $0.0398-0.0610).
    #
    # Capped at 2xlarge rather than naming bare families. A family name lets
    # Batch launch anything in it, and with `max_vcpus` at 16 that could be a
    # single 16-vCPU instance holding sixteen searches, all of which a single
    # reclaim would take out at once. Eight is enough blast radius.
    instance_type = [
      "m6i.large", "m6i.xlarge", "m6i.2xlarge",
      "m6a.large", "m6a.xlarge", "m6a.2xlarge",
      "m7i.large", "m7i.xlarge", "m7i.2xlarge",
      "m7a.large", "m7a.xlarge", "m7a.2xlarge",
      "m8i.large", "m8i.xlarge", "m8i.2xlarge",
      "m8a.large", "m8a.xlarge", "m8a.2xlarge",
    ]

    # No `image_id`. It was a hand-pasted AMI id, last built 2025-12-18, that
    # nothing would have told us was stale and that pins the fleet to one
    # architecture and one patch level by hand.
    #
    # `image_type` is the load-bearing half. The environment's *declared* type
    # was ECS_AL2 -- never set here, so AWS defaulted it, and the pinned AMI
    # (an AL2023 image) was overriding it, which is most likely why the pin
    # existed. Batch has blocked creating ECS environments on Batch-provided
    # Amazon Linux 2 AMIs since 2026-06-30, and every change in this block
    # replaces the environment, so dropping the pin without naming AL2023
    # would be rejected. ECS_AL2023 also resolves per architecture, which is
    # what a future arm environment would need instead of a second pin.
    #
    # Stated rather than left to the default so the choice is visible, and
    # `image_id` is deprecated in the Batch API in favour of this block.
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
