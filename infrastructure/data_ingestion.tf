data "archive_file" "data_ingestion_lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/data_ingestion/src"
  output_path = "${path.module}/lambdas/data_ingestion/build/data_ingestion_lambda.zip"
  excludes    = ["__pycache__/*", "*.pyc"]
}

data "archive_file" "data_ingestion_psycopg2_layer_package" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/data_ingestion/layer"
  output_path = "${path.module}/lambdas/data_ingestion/build/psycopg2_layer.zip"
  excludes    = ["__pycache__/*", "*.pyc"]
}

resource "aws_lambda_layer_version" "data_ingestion_psycopg2" {
  layer_name          = "${var.data_ingestion.function_name}-psycopg2"
  description         = "psycopg2-binary dependency for the data ingestion Lambda."
  filename            = data.archive_file.data_ingestion_psycopg2_layer_package.output_path
  source_code_hash    = data.archive_file.data_ingestion_psycopg2_layer_package.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

resource "aws_iam_role" "data_ingestion_lambda" {
  name = "${var.data_ingestion.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "data_ingestion_basic_execution" {
  role       = aws_iam_role.data_ingestion_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "data_ingestion_vpc_access" {
  role       = aws_iam_role.data_ingestion_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_security_group" "data_ingestion_lambda" {
  name        = "${var.data_ingestion.function_name}-lambda-sg"
  description = "Allow data ingestion Lambda to reach private resources"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lambda_function" "data_ingestion" {
  function_name = var.data_ingestion.function_name
  description   = "Ingests trade market listing JSON into PostgreSQL."

  role    = aws_iam_role.data_ingestion_lambda.arn
  handler = "lambda_function.handler"
  runtime = "python3.12"

  filename         = data.archive_file.data_ingestion_lambda_package.output_path
  source_code_hash = data.archive_file.data_ingestion_lambda_package.output_base64sha256

  layers = concat(
    [aws_lambda_layer_version.data_ingestion_psycopg2.arn],
    var.data_ingestion.lambda_layer_arns
  )

  timeout     = 30
  memory_size = 256

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.data_ingestion_lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.postgres.address
      DB_NAME     = aws_db_instance.postgres.db_name
      DB_PASSWORD = var.database.password
      DB_PORT     = tostring(aws_db_instance.postgres.port)
      DB_USER     = var.database.username
    }
  }
}

resource "aws_apigatewayv2_api" "data_ingestion" {
  name          = "${var.data_ingestion.function_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "data_ingestion_lambda" {
  api_id = aws_apigatewayv2_api.data_ingestion.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.data_ingestion.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "data_ingestion" {
  api_id = aws_apigatewayv2_api.data_ingestion.id

  route_key = "${var.data_ingestion.api_route_method} ${var.data_ingestion.api_route_path}"
  target    = "integrations/${aws_apigatewayv2_integration.data_ingestion_lambda.id}"
}

resource "aws_apigatewayv2_stage" "data_ingestion_default" {
  api_id = aws_apigatewayv2_api.data_ingestion.id

  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_data_ingestion_api_gateway" {
  statement_id  = "AllowDataIngestionApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_ingestion.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.data_ingestion.execution_arn}/*/*"
}
