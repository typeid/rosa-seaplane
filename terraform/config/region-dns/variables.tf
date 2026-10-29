variable "region" {
  type        = string
  description = "AWS region"
}

variable "deployment_name" {
  type        = string
  description = "Regional deployment name (rendered deployment_name)"
}

variable "environment_domain" {
  type        = string
  description = "Environment domain whose zone is in the central account (e.g. int0.rosa.devshift.net)"
}

variable "rc_account_id" {
  type        = string
  description = "RC account that holds the regional zone"
}

variable "rc_admin_role_name" {
  type        = string
  description = "Child admin role assumed in the RC account"
  default     = "OrganizationAccountAccessRole"
}
