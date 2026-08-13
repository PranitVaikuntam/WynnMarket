output "trade_market_listings_table_name" {
  description = "DynamoDB table name for trade market listings."
  value       = aws_dynamodb_table.trade_market_listings.name
}

output "trade_market_listings_table_arn" {
  description = "DynamoDB table ARN for trade market listings."
  value       = aws_dynamodb_table.trade_market_listings.arn
}

output "vpc_id" {
  description = "VPC ID for future compute resources."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for future compute resources."
  value       = aws_subnet.private[*].id
}

output "dynamodb_vpc_endpoint_id" {
  description = "DynamoDB gateway VPC endpoint ID."
  value       = aws_vpc_endpoint.dynamodb.id
}
