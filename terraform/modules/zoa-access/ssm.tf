# =============================================================================
# ZOA Deployment Autodiscovery — SSM Parameter Store
# =============================================================================
# Written into this (RC) account. Parameter name is deployment_name (Seaplane
# config: us-east-1 or us-east-1-eph-<id>), not regional_id (eph-<id>-regional).
#
# The ZOA CLI reads /zoa/deployments/<deployment_name> from the central account
# (primary + replica SSM regions). scripts/publish-zoa-discovery.sh copies this
# parameter there with central credentials, so the RC pipeline never accesses
# the central account.
#
# TODO: Rework ZOA deployment discovery so it no longer needs a central entry
# (rosa-seaplane-zoa CLI change, e.g. regional DNS or RC SSM lookup), and drop
# the central copy.
# =============================================================================

locals {
  deployment_ssm_value = jsonencode({
    access_url       = aws_lambda_function_url.access.function_url
    invoker_role_arn = aws_iam_role.invoker.arn
    region           = data.aws_region.current.name
    account_id       = data.aws_caller_identity.current.account_id
    deployment_name  = var.deployment_name
  })
}

resource "aws_ssm_parameter" "deployment" {
  name        = "/zoa/deployments/${var.deployment_name}"
  type        = "String"
  description = "ZOA deployment discovery for ${var.deployment_name}"

  value = local.deployment_ssm_value

  tags = merge(local.common_tags, {
    Name = "/zoa/deployments/${var.deployment_name}"
  })
}
