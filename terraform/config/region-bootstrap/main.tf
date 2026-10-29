# =============================================================================
# Region Bootstrap (RC account)
#
# Creates the pipeline infrastructure for the region's RC and MC pipelines.
# The regional hosted zone and its delegation are in terraform/config/region-dns.
# =============================================================================

# Applied with RC account credentials.
provider "aws" {
  region            = var.region
  use_fips_endpoint = can(regex("^(us|us-gov)-", var.region))
}

# Shared GitHub CodeStar Connection
# The bootstrap script ensures the connection exists in the RC account and
# imports it here so Terraform can reference the selected ARN without deleting
# it on teardown. During teardown, `terraform state rm` removes it before
# destroy so the connection persists across CI runs.
resource "aws_codestarconnections_connection" "github" {
  name          = "rosa-regional-github-shared"
  provider_type = "GitHub"

  lifecycle {
    prevent_destroy = true
  }
}

module "codepipeline_shared" {
  source = "../../modules/codepipeline-shared"

  github_connection_arn = aws_codestarconnections_connection.github.arn
  name_prefix           = var.name_prefix
  region                = var.region
  cluster_project_names = var.cluster_project_names
}

# CodeBuild Failure Notifications
# Gated by an explicit feature flag (see var.enable_slack_notifications).
# Monitors the RC/MC CodeBuild projects rendered at bootstrap time; rerun
# bootstrap to include clusters added later.
module "codebuild_notifications" {
  source = "../../modules/codebuild-notifications"
  count  = var.enable_slack_notifications ? 1 : 0

  slack_webhook_ssm_param = var.slack_webhook_ssm_param
  name_prefix             = var.name_prefix
  project_names           = var.cluster_project_names
}
