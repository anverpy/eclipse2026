# AEMET poller — public OpenData API, api_key header (no OAuth/registration wait).
data "archive_file" "aemet_lambda" {
  type        = "zip"
  output_path = "${path.module}/build/aemet_poller.zip"

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
    content  = file("${path.module}/../lambdas/aemet/__init__.py")
    filename = "lambdas/aemet/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/aemet/handler.py")
    filename = "lambdas/aemet/handler.py"
  }
}

resource "aws_lambda_function" "aemet_poller" {
  function_name = "${var.project}-aemet-poller"
  role          = aws_iam_role.poller["aemet"].arn
  handler       = "lambdas.aemet.handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.aemet_lambda.output_path
  source_code_hash = data.archive_file.aemet_lambda.output_base64sha256

  environment {
    variables = {
      DATA_LAKE_BUCKET = local.data_lake_bucket
      AEMET_API_KEY    = var.aemet_api_key
    }
  }

  depends_on = [aws_s3_bucket.data_lake]
}
