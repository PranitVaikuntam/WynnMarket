variable "aws_region" {
  description = "AWS region for WynnMarket infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for trade market listings."
  type        = string
  default     = "wynnmarket-trade-market-listings"
}

variable "vpc_cidr" {
  description = "CIDR block for the WynnMarket VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks for optional EC2 container hosts."
  type        = list(string)
  default     = ["10.0.101.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 1
    error_message = "Exactly one public subnet CIDR block is required."
  }
}

variable "ecr_repository_name" {
  description = "ECR repository name for the WynnMarket container image."
  type        = string
  default     = "wynnmarket"
}

variable "enable_app_instance" {
  description = "When true, create an EC2 instance that pulls and runs the ECR image."
  type        = bool
  default     = false
}

variable "app_instance_type" {
  description = "EC2 instance type for the optional container host."
  type        = string
  default     = "t3.medium"
}

variable "app_image_tag" {
  description = "Image tag the optional EC2 host should pull from ECR."
  type        = string
  default     = "latest"
}

variable "app_container_name" {
  description = "Docker container name used on the optional EC2 host."
  type        = string
  default     = "wynnmarket"
}
