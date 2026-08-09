# Public data feed for the GitHub Pages dashboard (docs/). Separate bucket
# from the data lake on purpose — the only thing exposed here is the
# aggregator's distilled snapshot (see lambdas/aggregator/handler.py), never
# the raw lake. Public access is via bucket policy only (block_public_acls
# stays true), scoped to the single `latest.json` object, not the bucket.
resource "aws_s3_bucket" "public_site" {
  bucket = "${var.project}-public"
}

resource "aws_s3_bucket_public_access_block" "public_site" {
  bucket                  = aws_s3_bucket.public_site.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "public_site_read" {
  statement {
    sid       = "PublicReadLatestSnapshot"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.public_site.arn}/latest.json"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "public_site_read" {
  bucket     = aws_s3_bucket.public_site.id
  policy     = data.aws_iam_policy_document.public_site_read.json
  depends_on = [aws_s3_bucket_public_access_block.public_site]
}

# GitHub Pages project-page origin for repo "eclipse2026" under the anverpy
# account (see CHANGELOG) — narrowed to this exact origin, not "*".
resource "aws_s3_bucket_cors_configuration" "public_site" {
  bucket = aws_s3_bucket.public_site.id

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["https://anverpy.github.io"]
    allowed_headers = ["*"]
    max_age_seconds = 300
  }
}
