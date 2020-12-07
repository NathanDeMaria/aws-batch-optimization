variable "instance_role_arn" {
  description = "ARN of the IAM role assumed by instances"
}

variable "security_group_id" {
  description = "ID of the security group to put instances in"
}

variable "subnet_id" {
  description = "ID of the subnet to put instances in"
}
