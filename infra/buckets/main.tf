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

# Versioning is an undo button for the data bucket, whose objects are
# rewritten in place: the season files are replaced wholesale by every daily
# job run, so a bad pull -- or a backfill that re-pulls twenty years of them
# in one go -- overwrites good data with no way back. Every writer of this
# bucket now merges rather than replaces, but that is a property of code that
# can regress; this is the one that holds regardless.
#
# Not on the temp bucket: everything there expires after seven days anyway,
# so versions would be pure cost.
#
# Worth knowing before applying: a bucket can be suspended back to
# unversioned, but never returned to never-versioned.
resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ...and this is what stops the undo button being an unbounded storage bill.
# The objects that matter here are rewritten daily, so the window is the whole
# cost dial: N days of retention means roughly N stale copies of each of them,
# and the steady-state bill is (bytes rewritten per day) x N.
#
# 30 days is chosen to be comfortably longer than it takes to notice a bad
# pull -- the job dashboard reports daily -- rather than to be a long archive.
# Halve it and the cost halves with it; the only thing lost is how far back a
# mistake can be undone.
resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # A noncurrent-version rule on a bucket whose versioning is still being
  # enabled is a race the provider documents; ordering them makes a first
  # apply behave like every subsequent one.
  depends_on = [aws_s3_bucket_versioning.bucket]
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
