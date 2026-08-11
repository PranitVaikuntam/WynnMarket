output "rds_endpoint" {
  description = "RDS hostname"
  value       = aws_db_instance.postgres.address
}

output "database_url" {
  description = "PostgreSQL connection URL without the password"
  value       = "postgresql://${var.database.username}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/wynnmarket"
  sensitive   = true
}

output "data_ingestion_function_name" {
  description = "Data ingestion Lambda function name."
  value       = aws_lambda_function.data_ingestion.function_name
}

output "data_ingestion_function_arn" {
  description = "Data ingestion Lambda function ARN."
  value       = aws_lambda_function.data_ingestion.arn
}

output "data_ingestion_api_endpoint" {
  description = "Public API Gateway endpoint for data ingestion."
  value       = "${aws_apigatewayv2_api.data_ingestion.api_endpoint}${var.data_ingestion.api_route_path}"
}
