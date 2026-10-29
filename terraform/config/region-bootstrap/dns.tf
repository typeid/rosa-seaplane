# Regional hosted zone (<deployment_name>.<environment_domain>). Its NS
# delegation lives in the central account (region-bootstrap-central). The RC
# Terraform looks the zone up by name and owns everything beneath it.

resource "aws_route53_zone" "regional" {
  count = var.environment_domain != null ? 1 : 0

  name = "${var.deployment_name}.${var.environment_domain}"

  tags = {
    Name     = "${var.deployment_name}.${var.environment_domain}"
    function = "dns"
    module   = "region-bootstrap"
  }
}
