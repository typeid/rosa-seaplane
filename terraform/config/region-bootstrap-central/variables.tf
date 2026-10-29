variable "region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "deployment_name" {
  type        = string
  description = "Regional deployment name (rendered deployment_name)"
}

variable "environment_domain" {
  type        = string
  description = "Environment domain whose zone is in this account (e.g. int0.rosa.devshift.net). Null skips the delegation."
  default     = null
}

variable "regional_name_servers" {
  type        = list(string)
  description = "Name servers of the regional zone (region-bootstrap output)"
  default     = []
}

