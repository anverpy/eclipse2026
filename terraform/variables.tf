variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "project" {
  description = "short project prefix, used in resource names/tags"
  type        = string
  default     = "eclipse2026"
}

variable "budget_limit_usd" {
  description = "monthly cost cap before alarm fires (see README cost target: ~10-20 USD worst case)"
  type        = number
  default     = 20
}

variable "alert_email" {
  description = "email for budget alarm notifications"
  type        = string
  default     = "andresw206@gmail.com"
}

variable "esios_token" {
  description = "personal API token for api.esios.ree.es (REE), set in terraform.tfvars — never commit the real value"
  type        = string
  sensitive   = true
}

variable "aemet_api_key" {
  description = "personal API key for opendata.aemet.es (AEMET), set in terraform.tfvars — never commit the real value"
  type        = string
  sensitive   = true
}
