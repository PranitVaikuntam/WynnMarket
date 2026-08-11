variable "database" {
  description = "Database deployment configuration."
  type = object({
    allowed_cidr = optional(string, "0.0.0.0/0")
    password     = string
    username     = optional(string, "postgresadmin")
  })
  sensitive = true
}

variable "data_ingestion" {
  description = "Data ingestion Lambda deployment configuration."
  type = object({
    api_route_method  = optional(string, "POST")
    api_route_path    = optional(string, "/market-items")
    api_stage_name    = optional(string, "prod")
    function_name     = optional(string, "wynnmarket-data-ingestion")
    lambda_layer_arns = optional(list(string), [])
  })
  default = {}
}
