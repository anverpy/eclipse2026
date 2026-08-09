# Aggregator — periodic Lambda that republishes today's data lake contents
# as one public JSON snapshot (see lambdas/aggregator/handler.py). Own role,
# same least-privilege-per-function pattern as the 5 source pollers (iam.tf,
# decision 7), kept separate from that file's `local.sources` map since this
# isn't an ingestion source.

data "archive_file" "aggregator_lambda" {
  type        = "zip"
  output_path = "${path.module}/build/aggregator.zip"

  source {
    content  = file("${path.module}/../lambdas/__init__.py")
    filename = "lambdas/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/aggregator/__init__.py")
    filename = "lambdas/aggregator/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/aggregator/handler.py")
    filename = "lambdas/aggregator/handler.py"
  }
}

resource "aws_iam_role" "aggregator" {
  name               = "${var.project}-aggregator-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "aggregator" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project}-aggregator:*"]
  }

  # cross-source read is a deliberate exception to the per-source prefix
  # scoping in iam.tf — this is the one function that legitimately needs to
  # see all 5 sources at once to build the combined snapshot.
  statement {
    sid       = "ListDataLake"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data_lake.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["source=*/dt=*"]
    }
  }
  statement {
    sid       = "ReadDataLake"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/source=*"]
  }

  statement {
    sid       = "WriteSnapshot"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.public_site.arn}/latest.json"]
  }
}

resource "aws_iam_role_policy" "aggregator" {
  name   = "${var.project}-aggregator-policy"
  role   = aws_iam_role.aggregator.id
  policy = data.aws_iam_policy_document.aggregator.json
}

resource "aws_lambda_function" "aggregator" {
  function_name = "${var.project}-aggregator"
  role          = aws_iam_role.aggregator.arn
  handler       = "lambdas.aggregator.handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.aggregator_lambda.output_path
  source_code_hash = data.archive_file.aggregator_lambda.output_base64sha256

  environment {
    variables = {
      DATA_LAKE_BUCKET = local.data_lake_bucket
      PUBLIC_BUCKET    = aws_s3_bucket.public_site.bucket
    }
  }

  depends_on = [aws_s3_bucket.data_lake, aws_s3_bucket.public_site]
}
