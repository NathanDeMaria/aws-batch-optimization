output "named_urls" {
  value = { for name, repo in aws_ecr_repository.repos : name => repo.repository_url }
}
