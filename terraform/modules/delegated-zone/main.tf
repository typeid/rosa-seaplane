# A hosted zone in one account, delegated from its parent zone in another.
# Zone and delegation share one state, so Terraform passes the name servers
# and removes the delegation before the zone on destroy.

data "aws_route53_zone" "parent" {
  provider = aws.parent

  name         = var.parent_zone_name
  private_zone = false
}

resource "aws_route53_zone" "this" {
  provider = aws.child

  name = var.zone_name

  tags = {
    Name     = var.zone_name
    function = "dns"
    module   = "delegated-zone"
  }
}

resource "aws_route53_record" "delegation" {
  provider = aws.parent

  zone_id = data.aws_route53_zone.parent.zone_id
  name    = aws_route53_zone.this.name
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.this.name_servers
}
