variable "name_prefix" {
  type        = string
  description = "Optional prefix for resource names (e.g., CI run hash for parallel e2e runs)"
  default     = ""
}

variable "region" {
  type        = string
  description = "AWS Region for the Pipeline Infrastructure"
  default     = "us-east-1"
}

variable "deployment_name" {
  type        = string
  description = "Regional deployment name (rendered deployment_name). Names the regional zone."
}

variable "cluster_project_names" {
  type        = list(string)
  description = "Rendered RC and MC project names (used for failure notifications and pipeline permissions)."
  default     = []
}

variable "environment_domain" {
  type        = string
  description = "Environment domain (e.g. int0.rosa.devshift.net). Null skips the regional zone."
  default     = null
}

variable "enable_slack_notifications" {
  type        = bool
  description = "Enable Slack notifications for CodeBuild failures. When true, slack_webhook_ssm_param must exist in the RC account."
  default     = false
}

variable "slack_webhook_ssm_param" {
  type        = string
  description = "SSM Parameter Store path (RC account) containing the Slack webhook URL"
  default     = "/rosa-regional/slack/webhook-url"
}
