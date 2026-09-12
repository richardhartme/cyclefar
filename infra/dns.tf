resource "aws_route53_record" "application" {
  count = var.route53_zone_id == null ? 0 : 1

  zone_id         = var.route53_zone_id
  name            = var.domain_name
  type            = "A"
  ttl             = 300
  records         = [ aws_eip.application.public_ip ]
  allow_overwrite = true
}
