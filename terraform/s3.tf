# data lake bucket — single bucket, prefixed per source (see iam.tf locals + policies).
resource "aws_s3_bucket" "data_lake" {
  bucket = local.data_lake_bucket
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
