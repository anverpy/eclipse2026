# Google Trends poller — unofficial/scraped API, best-effort per README (low
# priority, must not block the rest of the pipeline). Pure stdlib, no layer needed.
data "archive_file" "trends_lambda" {
  type        = "zip"
  output_path = "${path.module}/build/trends_poller.zip"

  source {
    content  = file("${path.module}/../lambdas/__init__.py")
    filename = "lambdas/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/common/__init__.py")
    filename = "lambdas/common/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/common/envelope.py")
    filename = "lambdas/common/envelope.py"
  }
  source {
    content  = file("${path.module}/../lambdas/common/s3_writer.py")
    filename = "lambdas/common/s3_writer.py"
  }
  source {
    content  = file("${path.module}/../lambdas/trends/__init__.py")
    filename = "lambdas/trends/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/trends/handler.py")
    filename = "lambdas/trends/handler.py"
  }
}

resource "aws_lambda_function" "trends_poller" {
  function_name = "${var.project}-trends-poller"
  role          = aws_iam_role.poller["trends"].arn
  handler       = "lambdas.trends.handler.handler"
  runtime       = "python3.12"
  timeout       = 20
  memory_size   = 128

  filename         = data.archive_file.trends_lambda.output_path
  source_code_hash = data.archive_file.trends_lambda.output_base64sha256

  environment {
    variables = {
      DATA_LAKE_BUCKET = local.data_lake_bucket
    }
  }

  depends_on = [aws_s3_bucket.data_lake]
}
