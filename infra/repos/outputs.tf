output "named_urls" {
  value = { for name, repo in aws_ecr_repository.repos : name => repo.repository_url }
}

# IAM user details for ECR access
output "ecr_iam_users" {
  value = {
    for name, user in aws_iam_user.ecr_pusher :
    name => {
      user_arn  = user.arn
      user_name = user.name
      access_key = aws_iam_access_key.ecr_access_key[name].id
      secret_key = aws_iam_access_key.ecr_access_key[name].secret
      encrypted_secret = aws_iam_access_key.ecr_access_key[name].encrypted_secret
    }
  }
  sensitive = true
}


