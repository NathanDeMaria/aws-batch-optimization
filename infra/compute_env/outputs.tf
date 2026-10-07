output "arn" {
  value = aws_batch_compute_environment.compute.arn
}

# The ECS cluster Batch runs this environment's instances in, for the debug
# role to read which instance a job is on (debug.tf).
output "ecs_cluster_arn" {
  value = aws_batch_compute_environment.compute.ecs_cluster_arn
}
