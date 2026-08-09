# Athena: dedicated results bucket + workgroup with a per-query bytes-scanned
# cap (cost guardrail, matches README cost goal — single-day low-volume event).

resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.project}-athena-results"
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_athena_workgroup" "eclipse2026" {
  name = "${var.project}-wg"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 1073741824 # 1 GiB/query safety cap

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
    }
  }
}
