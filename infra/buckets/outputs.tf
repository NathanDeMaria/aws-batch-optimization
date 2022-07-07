output "arns" {
  value = [
    aws_s3_bucket.bucket.arn,
    aws_s3_bucket.temp_bucket.arn,
  ]
}

output "bucket_name" {
  value = aws_s3_bucket.bucket.bucket
}

output "temp_bucket_name" {
  value = aws_s3_bucket.temp_bucket.bucket
}
