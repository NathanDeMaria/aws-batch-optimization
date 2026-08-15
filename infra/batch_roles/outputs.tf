output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "scheduler_role_arn" {
  value = aws_iam_role.scheduler.arn
}
