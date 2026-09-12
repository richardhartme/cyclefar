variable "aws_region" {
  description = "AWS region in which to create the infrastructure."
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Short project name used in resource names and tags."
  type        = string
  default     = "cyclefar"
}

variable "environment" {
  description = "Deployment environment used in resource names and tags."
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for the CycleFar VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public application subnet."
  type        = string
  default     = "10.20.0.0/24"
}

variable "database_subnet_cidrs" {
  description = "Two private subnet CIDR blocks for the RDS DB subnet group."
  type        = list(string)
  default     = [ "10.20.1.0/24", "10.20.2.0/24" ]

  validation {
    condition     = length(var.database_subnet_cidrs) == 2
    error_message = "Provide exactly two database subnet CIDRs for the RDS DB subnet group."
  }
}

variable "ec2_instance_type" {
  description = "EC2 instance type for the single Docker/Kamal application server."
  type        = string
  default     = "t3a.small"
}

variable "ubuntu_ami_id" {
  description = "Optional Ubuntu AMI ID. Leave null to use Canonical's current Ubuntu 24.04 LTS AMD64 AMI from SSM Parameter Store."
  type        = string
  default     = null
  nullable     = true
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair. Set this or ssh_public_key."
  type        = string
  default     = null
  nullable     = true
}

variable "ssh_public_key" {
  description = "OpenSSH public key to register as a new EC2 key pair. Set this or ssh_key_name."
  type        = string
  default     = null
  nullable     = true
}

variable "ssh_allowed_cidrs" {
  description = "CIDR ranges allowed to SSH to the application server. Restrict this to trusted addresses for real use."
  type        = list(string)
  default     = []
}

variable "rds_instance_class" {
  description = "RDS instance class for PostgreSQL."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_engine_version" {
  description = "Optional RDS PostgreSQL engine version. Leave null to use AWS's regional default."
  type        = string
  default     = null
  nullable     = true
}

variable "database_name" {
  description = "Initial PostgreSQL database name. RDS database names may contain only letters and numbers."
  type        = string
  default     = "cyclefarproduction"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]*$", var.database_name))
    error_message = "database_name must begin with a letter and contain only letters and numbers."
  }
}

variable "database_username" {
  description = "Master username for the RDS PostgreSQL instance."
  type        = string
  default     = "cyclefar"
}

variable "database_password" {
  description = "Optional RDS master password. Leave null to generate a password with the random provider."
  type        = string
  default     = null
  nullable     = true
  sensitive    = true
}

variable "rds_skip_final_snapshot" {
  description = "Whether terraform destroy skips the final RDS snapshot. Keep false for production data."
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Optional existing Route 53 hosted zone ID for the domain. No hosted zone is created by this configuration."
  type        = string
  default     = null
  nullable     = true
}

variable "domain_name" {
  description = "Domain name for the optional Route 53 A record."
  type        = string
  default     = "cyclefar.com"
}
