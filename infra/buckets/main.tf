resource "aws_s3_bucket" "bucket" {
  bucket = "${var.prefix}-batch-bucket"
}

resource "aws_s3_bucket" "temp_bucket" {
  bucket = "${var.prefix}-batch-temp-bucket"

  lifecycle_rule {
    enabled = true

    expiration {
      days = 7
    }
  }
}
