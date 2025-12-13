resource "aws_s3_bucket" "bucket" {
  bucket = "${var.prefix}-batch-bucket"
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket" "temp_bucket" {
  bucket = "${var.prefix}-batch-temp-bucket"

  lifecycle_rule {
    enabled = true

    expiration {
      days = 7
    }
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}
