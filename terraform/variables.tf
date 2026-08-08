variable "db_username" {
  description = "RDS administrator username"
  type        = string
  default     = "postgresadmin"
}

variable "db_password" {
  description = "RDS administrator password"
  type        = string
  sensitive   = true
}

variable "allowed_cidr" {
  description = "IP address allowed to connect, such as 203.0.113.10/32"
  type        = string
  default = "0.0.0.0/0"
}