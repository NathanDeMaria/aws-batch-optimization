resource "aws_s3_bucket" "bucket" {
  bucket = "${var.prefix}-batch-bucket"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "temp_bucket" {
  bucket = "${var.prefix}-batch-temp-bucket"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "temp_bucket" {
  bucket = aws_s3_bucket.temp_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "temp_bucket" {
  bucket = aws_s3_bucket.temp_bucket.id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}
