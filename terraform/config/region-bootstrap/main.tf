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
# Created (and authorized by hand) by the bootstrap script, and only looked up
# here, so destroying this root never deletes it.
data "aws_codestarconnections_connection" "github" {
  name = "rosa-regional-github-shared"
}

locals {
  # The platform image is pulled from another account's ECR by the MC role.
  platform_image_repository = try(regex("^([0-9]{12})\\.dkr\\.ecr\\.([a-z0-9-]+)\\.amazonaws\\.com/([^:@]+)", var.platform_image), null)
}

module "codepipeline_shared" {
  source = "../../modules/codepipeline-shared"

  github_connection_arn = data.aws_codestarconnections_connection.github.arn
  name_prefix           = var.name_prefix
  region                = var.region
  regional_id           = var.regional_id
  cluster_project_names = var.cluster_project_names
  platform_image_repository_arn = local.platform_image_repository == null ? null : (
    "arn:aws:ecr:${local.platform_image_repository[1]}:${local.platform_image_repository[0]}:repository/${local.platform_image_repository[2]}"
  )
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
