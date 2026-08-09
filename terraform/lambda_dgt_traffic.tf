# DGT traffic poller — public DATEX2 feed (nap.dgt.es), no API key needed.
data "archive_file" "dgt_traffic_lambda" {
  type        = "zip"
  output_path = "${path.module}/build/dgt_traffic_poller.zip"

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
    content  = file("${path.module}/../lambdas/dgt_traffic/__init__.py")
    filename = "lambdas/dgt_traffic/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/dgt_traffic/handler.py")
    filename = "lambdas/dgt_traffic/handler.py"
  }
}

resource "aws_lambda_function" "dgt_traffic_poller" {
  function_name = "${var.project}-dgt-traffic-poller"
  role          = aws_iam_role.poller["dgt_traffic"].arn
  handler       = "lambdas.dgt_traffic.handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.dgt_traffic_lambda.output_path
  source_code_hash = data.archive_file.dgt_traffic_lambda.output_base64sha256

  environment {
    variables = {
      DATA_LAKE_BUCKET = local.data_lake_bucket
    }
  }

  depends_on = [aws_s3_bucket.data_lake]
}
