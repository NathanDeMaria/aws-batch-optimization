output "arn" {
  description = "Revision-specific ARN. Pins a submission to exactly this definition."
  value       = aws_batch_job_definition.this.arn
}

output "name" {
  description = "Definition name. Submitting by name gets the latest active revision, which is usually what a launcher wants."
  value       = aws_batch_job_definition.this.name
}
