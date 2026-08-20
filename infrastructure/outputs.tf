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

output "public_subnet_ids" {
  description = "Public subnet IDs for optional EC2 container hosts."
  value       = aws_subnet.public[*].id
}

output "aws_region" {
  description = "AWS region used by this Terraform workspace."
  value       = var.aws_region
}

output "ecr_repository_name" {
  description = "ECR repository name for the WynnMarket image."
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  description = "ECR repository URL for Docker tagging and pushing."
  value       = aws_ecr_repository.app.repository_url
}

output "app_instance_id" {
  description = "EC2 instance ID when enable_app_instance is true."
  value       = try(aws_instance.app[0].id, null)
}

output "app_instance_public_ip" {
  description = "Public IP for the optional EC2 container host."
  value       = try(aws_instance.app[0].public_ip, null)
}
