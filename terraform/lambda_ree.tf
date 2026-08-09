# REE poller — first source deployed end-to-end (see README "siguiente paso").
# packaged explicitly file-by-file (not the whole lambdas/ dir) so the zip never
# picks up terraform/ secrets or the other 4 sources' unfinished code.
data "archive_file" "ree_lambda" {
  type        = "zip"
  output_path = "${path.module}/build/ree_poller.zip"

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
    content  = file("${path.module}/../lambdas/ree/__init__.py")
    filename = "lambdas/ree/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/ree/handler.py")
    filename = "lambdas/ree/handler.py"
  }
}

resource "aws_lambda_function" "ree_poller" {
  function_name = "${var.project}-ree-poller"
  role          = aws_iam_role.poller["ree"].arn
  handler       = "lambdas.ree.handler.handler"
  runtime       = "python3.12"
  timeout       = 20
  memory_size   = 128

  filename         = data.archive_file.ree_lambda.output_path
  source_code_hash = data.archive_file.ree_lambda.output_base64sha256

  environment {
    variables = {
      DATA_LAKE_BUCKET = local.data_lake_bucket
      ESIOS_TOKEN       = var.esios_token
    }
  }

  depends_on = [aws_s3_bucket.data_lake]
}
