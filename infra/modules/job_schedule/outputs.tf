output "arn" {
  description = "ARN of the schedule"
  value       = aws_scheduler_schedule.this.arn
}

output "name" {
  description = "Name of the schedule"
  value       = aws_scheduler_schedule.this.name
}
