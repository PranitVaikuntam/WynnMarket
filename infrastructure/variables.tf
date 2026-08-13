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

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks for future compute resources."
  type        = list(string)
  default     = ["10.0.1.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 1
    error_message = "Exactly one private subnet CIDR block is required."
  }
}
