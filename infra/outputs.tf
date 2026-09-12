output "application_server_public_ip" {
  description = "Elastic IP for the CycleFar application server; use this as the Kamal web host."
  value       = aws_eip.application.public_ip
}

output "application_server_public_dns" {
  description = "AWS public DNS name for the CycleFar application server."
  value       = aws_instance.application.public_dns
}

output "application_server_ssh_user" {
  description = "Default SSH user for the Ubuntu AMI."
  value       = "ubuntu"
}

output "database_endpoint" {
  description = "Private RDS PostgreSQL endpoint for DB_HOST."
  value       = aws_db_instance.database.address
}

output "database_port" {
  description = "PostgreSQL port for DB_PORT."
  value       = aws_db_instance.database.port
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_db_instance.database.db_name
}

output "database_username" {
  description = "RDS PostgreSQL username for DB_USERNAME."
  value       = aws_db_instance.database.username
}

output "database_password" {
  description = "Sensitive RDS PostgreSQL password for DB_PASSWORD."
  value       = local.database_password
  sensitive   = true
}

output "route53_record_name" {
  description = "FQDN of the optional Route 53 record, or null when no hosted zone ID was supplied."
  value       = try(aws_route53_record.application[0].fqdn, null)
}
