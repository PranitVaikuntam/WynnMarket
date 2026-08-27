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

variable "wynncraft_server_address" {
  description = "Minecraft server address passed to the unattended supervisor."
  type        = string
  default     = "play.wynncraft.com"
}

variable "startup_timeout_seconds" {
  description = "Maximum time from container launch to the first valid Trade Market scan."
  type        = number
  default     = 600

  validation {
    condition     = var.startup_timeout_seconds >= 60
    error_message = "startup_timeout_seconds must be at least 60."
  }
}

variable "scan_timeout_seconds" {
  description = "Maximum permitted age of the last valid Trade Market scan."
  type        = number
  default     = 600

  validation {
    condition     = var.scan_timeout_seconds >= 60 && var.scan_timeout_seconds % 60 == 0
    error_message = "scan_timeout_seconds must be at least 60 and divisible by 60."
  }
}

variable "health_marker_path" {
  description = "Absolute in-container path updated after every valid scan."
  type        = string
  default     = "/tmp/wynnmarket/last-valid-scan"

  validation {
    condition     = startswith(var.health_marker_path, "/")
    error_message = "health_marker_path must be absolute."
  }
}

variable "enable_auth_volume" {
  description = "Create the dedicated encrypted EBS volume for HeadlessMC account state."
  type        = bool
  default     = true
}

variable "auth_volume_size_gib" {
  description = "Size of the encrypted HeadlessMC auth volume."
  type        = number
  default     = 1

  validation {
    condition     = var.auth_volume_size_gib >= 1
    error_message = "auth_volume_size_gib must be at least 1 GiB."
  }
}

variable "auth_volume_type" {
  description = "EBS volume type for the HeadlessMC auth file."
  type        = string
  default     = "gp3"
}

variable "auth_volume_kms_key_id" {
  description = "Optional customer-managed KMS key ARN or ID; null uses the AWS-managed EBS key."
  type        = string
  default     = null
}

variable "auth_volume_device_name" {
  description = "EC2 attachment name for the dedicated auth volume."
  type        = string
  default     = "/dev/sdf"
}

variable "auth_state_migrated" {
  description = "Explicit gate confirming .accounts.json has been migrated to the encrypted volume."
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "Retention for container output in CloudWatch Logs."
  type        = number
  default     = 14
}

variable "alert_email" {
  description = "Optional email destination for SNS alarm notifications."
  type        = string
  default     = null

  validation {
    condition     = var.alert_email == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be null or a valid email address."
  }
}
