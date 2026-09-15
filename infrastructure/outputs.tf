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

output "public_subnet_id" {
  description = "Public subnet ID for the EC2 container host."
  value       = aws_subnet.public.id
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
  description = "EC2 instance ID for the container host."
  value       = aws_instance.app.id
}

output "app_instance_public_ip" {
  description = "Public IP for the EC2 container host."
  value       = aws_instance.app.public_ip
}

output "web_url" {
  description = "Public HTTP URL for the WynnMarket web application."
  value       = "http://${aws_instance.app.public_ip}"
}

output "auth_volume_id" {
  description = "Dedicated encrypted EBS volume containing only HeadlessMC .accounts.json."
  value       = aws_ebs_volume.auth.id
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group receiving WynnMarket container output."
  value       = aws_cloudwatch_log_group.app.name
}

output "alarm_topic_arn" {
  description = "SNS topic used for ALARM and recovery notifications."
  value       = aws_sns_topic.alarms.arn
}
