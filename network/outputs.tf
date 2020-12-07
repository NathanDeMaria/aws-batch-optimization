output "security_group_id" {
  value = aws_security_group.vpc_sg.id
}

output "subnet_id" {
  value = aws_subnet.subnet.id
}
