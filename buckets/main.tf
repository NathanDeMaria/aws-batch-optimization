resource "aws_s3_bucket" "bucket" {
  bucket = "nathan-batch-temp-bucket"

  lifecycle_rule {
    enabled = true

    expiration {
      days = 7
    }
  }
}
