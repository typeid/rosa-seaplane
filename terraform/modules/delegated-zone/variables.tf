variable "zone_name" {
  type        = string
  description = "Name of the zone to create in the child account (e.g. us-east-1.int0.rosa.devshift.net)"
}

variable "parent_zone_name" {
  type        = string
  description = "Name of the public parent zone in the parent account (e.g. int0.rosa.devshift.net)"
}
