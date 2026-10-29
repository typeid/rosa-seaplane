# =============================================================================
# Region Bootstrap (central account)
#
# The central-account half of a region's bootstrap, applied with central
# credentials after terraform/config/region-bootstrap (RC account): the NS
# delegation of the regional zone in the environment zone.
# =============================================================================

provider "aws" {
  region            = var.region
  use_fips_endpoint = can(regex("^(us|us-gov)-", var.region))
}

data "aws_route53_zone" "environment" {
  count = var.environment_domain != null ? 1 : 0

  name         = var.environment_domain
  private_zone = false
}

resource "aws_route53_record" "regional_delegation" {
  count = var.environment_domain != null ? 1 : 0

  zone_id = data.aws_route53_zone.environment[0].zone_id
  name    = "${var.deployment_name}.${var.environment_domain}"
  type    = "NS"
  ttl     = 300
  records = var.regional_name_servers
}
