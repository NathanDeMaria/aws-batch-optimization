resource "aws_iam_role" "spot_fleet_role" {
  name = "spot-fleet-role"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Principal : {
          Service : "spotfleet.amazonaws.com"
        },
        Action : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "spot_fleet_policy" {
  name = "spot-fleet-policy"
  role = aws_iam_role.spot_fleet_role.id

  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : [
          "ec2:DescribeImages",
          "ec2:DescribeSubnets",
          "ec2:RequestSpotInstances",
          "ec2:TerminateInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:CreateTags",
          "ec2:RunInstances"
        ],
        Resource : [
          "*"
        ]
      },
      {
        Effect : "Allow",
        Action : "iam:PassRole",
        Condition : {
          StringEquals : {
            "iam:PassedToService" : [
              "ec2.amazonaws.com",
              "ec2.amazonaws.com.cn"
            ]
          }
        },
        Resource : [
          "*"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer"
        ],
        Resource : [
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/*"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "elasticloadbalancing:RegisterTargets"
        ],
        Resource : [
          "arn:aws:elasticloadbalancing:*:*:*/*"
        ]
      }
    ]
  })
}
