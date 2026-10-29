# =============================================================================
# Region DNS
#
# The regional hosted zone (<deployment_name>.<environment_domain>) in the RC
# account, delegated from the environment zone in the central account. Applied
# by scripts/bootstrap-region.sh with central credentials; the RC provider
# assumes the RC account's child admin role. The RC Terraform looks the zone up
# by name and owns everything beneath it.
# =============================================================================

provider "aws" {
  alias             = "central"
  region            = var.region
  use_fips_endpoint = can(regex("^(us|us-gov)-", var.region))
}

provider "aws" {
  alias             = "rc"
  region            = var.region
  use_fips_endpoint = can(regex("^(us|us-gov)-", var.region))

  assume_role {
    role_arn     = "arn:aws:iam::${var.rc_account_id}:role/${var.rc_admin_role_name}"
    session_name = "region-dns"
  }
}

module "regional_zone" {
  source = "../../modules/delegated-zone"

  providers = {
    aws.child  = aws.rc
    aws.parent = aws.central
  }

  zone_name        = "${var.deployment_name}.${var.environment_domain}"
  parent_zone_name = var.environment_domain
}
