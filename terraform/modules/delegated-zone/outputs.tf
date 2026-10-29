output "zone_id" {
  description = "ID of the delegated zone"
  value       = aws_route53_zone.this.zone_id
}
