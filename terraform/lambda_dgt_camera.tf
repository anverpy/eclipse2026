# DGT camera poller — needs Pillow (brightness calc), which isn't in the base
# Lambda runtime. Built as a layer via pip (manylinux wheel, no local build/
# Docker needed) rather than vendoring a compiled dependency into the repo.
locals {
  pillow_version   = "11.0.0"
  pillow_build_dir = "${path.module}/build/pillow_layer/python"
}

resource "null_resource" "pillow_layer_build" {
  triggers = {
    pillow_version = local.pillow_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${local.pillow_build_dir}
      mkdir -p ${local.pillow_build_dir}
      python3 -m pip install \
        --platform manylinux2014_x86_64 \
        --target=${local.pillow_build_dir} \
        --implementation cp \
        --python-version 3.12 \
        --only-binary=:all: \
        --no-deps \
        "Pillow==${local.pillow_version}"
    EOT
  }
}

data "archive_file" "pillow_layer" {
  type        = "zip"
  source_dir  = "${path.module}/build/pillow_layer"
  output_path = "${path.module}/build/pillow_layer.zip"
  depends_on  = [null_resource.pillow_layer_build]
}

resource "aws_lambda_layer_version" "pillow" {
  layer_name          = "${var.project}-pillow"
  filename            = data.archive_file.pillow_layer.output_path
  source_code_hash    = data.archive_file.pillow_layer.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

data "archive_file" "dgt_camera_lambda" {
  type        = "zip"
  output_path = "${path.module}/build/dgt_camera_poller.zip"

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
    content  = file("${path.module}/../lambdas/dgt_camera/__init__.py")
    filename = "lambdas/dgt_camera/__init__.py"
  }
  source {
    content  = file("${path.module}/../lambdas/dgt_camera/handler.py")
    filename = "lambdas/dgt_camera/handler.py"
  }
}

resource "aws_lambda_function" "dgt_camera_poller" {
  function_name = "${var.project}-dgt-camera-poller"
  role          = aws_iam_role.poller["dgt_camera"].arn
  handler       = "lambdas.dgt_camera.handler.handler"
  runtime       = "python3.12"
  # 60s covers a single-tick (normal-tier) run; tight-tier ticks 3x with a
  # 20s sleep between each (see handler.py), so needs headroom above 60s.
  timeout     = 90
  memory_size = 512
  layers      = [aws_lambda_layer_version.pillow.arn]

  filename         = data.archive_file.dgt_camera_lambda.output_path
  source_code_hash = data.archive_file.dgt_camera_lambda.output_base64sha256

  environment {
    variables = {
      DATA_LAKE_BUCKET = local.data_lake_bucket
    }
  }

  depends_on = [aws_s3_bucket.data_lake]
}
