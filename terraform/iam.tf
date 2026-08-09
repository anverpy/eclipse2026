data "aws_caller_identity" "current" {}

# names for downstream resources (S3 bucket, Kinesis stream, DynamoDB table)
# not yet created — kept as locals so IAM can ship ahead of them without
# implicit resource dependencies, and so the eventual resources reuse the
# same names.
locals {
  data_lake_bucket  = "${var.project}-data-lake"
  ree_stream_name   = "${var.project}-ree-stream"
  camera_table_name = "${var.project}-camera-brightness"

  # source key -> extra permissions beyond the common logs+S3 baseline
  sources = {
    ree         = { kinesis = true, dynamodb = false }
    aemet       = { kinesis = false, dynamodb = false }
    dgt_traffic = { kinesis = false, dynamodb = false }
    trends      = { kinesis = false, dynamodb = false }
    dgt_camera  = { kinesis = false, dynamodb = true }
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "poller" {
  for_each           = local.sources
  name               = "${var.project}-${replace(each.key, "_", "-")}-poller-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "poller" {
  for_each = local.sources

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project}-${replace(each.key, "_", "-")}-poller:*"]
  }

  statement {
    sid       = "S3Write"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.data_lake_bucket}/source=${each.key}/*"]
  }

  dynamic "statement" {
    for_each = each.value.kinesis ? [1] : []
    content {
      sid       = "KinesisWrite"
      actions   = ["kinesis:PutRecord", "kinesis:PutRecords"]
      resources = ["arn:aws:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/${local.ree_stream_name}"]
    }
  }

  dynamic "statement" {
    for_each = each.value.dynamodb ? [1] : []
    content {
      sid       = "DynamoWrite"
      actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
      resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.camera_table_name}"]
    }
  }
}

resource "aws_iam_role_policy" "poller" {
  for_each = local.sources
  name     = "${var.project}-${replace(each.key, "_", "-")}-poller-policy"
  role     = aws_iam_role.poller[each.key].id
  policy   = data.aws_iam_policy_document.poller[each.key].json
}
