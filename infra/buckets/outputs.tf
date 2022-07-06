output "arns" {
  value = [
    aws_s3_bucket.bucket.arn,
    aws_s3_bucket.temp_bucket.arn,
  ]
}
